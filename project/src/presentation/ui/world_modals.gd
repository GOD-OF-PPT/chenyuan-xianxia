class_name WorldModals
extends Control
## 第三层世界交互模态窗总成（全部干净挂载与销毁，严守 >=16px 字号、Space 100% 屏蔽与二次确认防呆）：
## 1. 青铜丹炉（首炼 15 秒文武控火三段调和 + 极品永久解锁滑块一键速炼）
## 2. 药肆交易与散修小地摊（【断玉剑匣】靠近蒙尘残铁片泛起温热微光与玉鸣 + >=60灵石二次确认）
## 3. 引灵石碑（回满气血清暗伤 + 篝火夜话触发 + 已点亮石碑快速传送）
## 4. 青岚手绘舆图（M 键，仅绘淡墨线索范围圈，零自动寻路）
## 5. 道卷存取（20 手动槽 + 3 滚动自动槽）与器物设置（4 总线音量 + 后台静音 + 无障碍 + 键位冲突检测改键）
## 6. 第一章通关结卷铭文

signal night_talk_selected(dialogue_id: String)
signal stele_teleport_selected(target_zone: String, spawn_tag: String, stele_id: String)
signal peddler_treasure_bought()
signal save_loaded_reload_zone()
signal return_to_title_requested()

var audio_director: AudioDirector = null
var is_standalone_on_title: bool = false

var _backdrop: ColorRect
var _card: PanelContainer
var _card_vbox: VBoxContainer
var _active_kind: String = ""

## 首炼 15 秒文武控火实时状态
var _brew_running: bool = false
var _brew_recipe_id: String = ""
var _brew_elapsed: float = 0.0
var _brew_heat: float = 0.50
var _brew_targets: Array = [0.35, 0.65, 0.40]
var _brew_recorded: Array[float] = []
var _brew_stage_lbl: Label = null
var _brew_target_lbl: Label = null
var _brew_heat_bar: ColorRect = null
var _brew_target_marker: ColorRect = null

## 键鼠自定义改键监听状态
var _rebinding_action: String = ""
var _rebind_status_lbl: Label = null


func _ready() -> void:
	UIThemeBuilder.bind_full_rect(self)
	visible = false
	theme = UIThemeBuilder.get_global_theme()

	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.05, 0.04, 0.04, 0.80)
	add_child(_backdrop)
	UIThemeBuilder.bind_full_rect(_backdrop)

	var center: CenterContainer = CenterContainer.new()
	add_child(center)
	UIThemeBuilder.bind_full_rect(center)

	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(1220.0, 680.0)
	var card_sb: StyleBoxFlat = UIThemeBuilder.make_xuan_paper_box(Color("#6E5233"), 3)
	card_sb.content_margin_left = 28.0
	card_sb.content_margin_right = 28.0
	card_sb.content_margin_top = 20.0
	card_sb.content_margin_bottom = 22.0
	_card.add_theme_stylebox_override("panel", card_sb)
	center.add_child(_card)

	_card_vbox = VBoxContainer.new()
	_card_vbox.add_theme_constant_override("separation", 12)
	_card.add_child(_card_vbox)


func close_modal() -> void:
	_brew_running = false
	_rebinding_action = ""
	if not visible:
		return
	visible = false
	_active_kind = ""
	if not is_standalone_on_title:
		InputRouter.set_mode(InputRouter.MODE_WORLD_COMBAT)
	if audio_director != null:
		audio_director.play_sfx("sfx_ui_jade_click", AudioDirector.TIER_B, true)


func _open_base(kind: String, min_size: Vector2 = Vector2(1180.0, 740.0)) -> void:
	_brew_running = false
	_rebinding_action = ""
	_active_kind = kind
	_card.custom_minimum_size = min_size
	for ch: Node in _card_vbox.get_children():
		ch.queue_free()
	visible = true
	InputRouter.set_mode(InputRouter.MODE_BREW_MINIGAME if kind == "alchemy_active" else InputRouter.MODE_MODAL_MENU)


func _add_header(title_txt: String) -> void:
	var hb: HBoxContainer = HBoxContainer.new()
	_card_vbox.add_child(hb)
	var tl: Label = Label.new()
	tl.text = title_txt
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.add_theme_font_size_override("font_size", UIThemeBuilder.FS_HEADER)
	tl.add_theme_color_override("font_color", Color("#5A3320"))
	hb.add_child(tl)

	var cb: Button = Button.new()
	cb.text = tr("UI_BTN_CLOSE")
	cb.focus_mode = Control.FOCUS_NONE
	cb.pressed.connect(close_modal)
	hb.add_child(cb)


## ==================== 1. 济世药庐青铜丹炉（15s 文武控火 + 速炼） ====================
func open_alchemy_furnace(selected_rid: String = "") -> void:
	_open_base("alchemy", Vector2(1120.0, 680.0))
	_add_header("【济世药庐 · 青铜丹炉】首炼文武控火与速炼")

	if selected_rid == "" and not CampaignState.unlocked_recipes.is_empty():
		selected_rid = CampaignState.unlocked_recipes[0]
	_brew_recipe_id = selected_rid

	var cols: HBoxContainer = HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 18)
	_card_vbox.add_child(cols)

	var left_v: VBoxContainer = VBoxContainer.new()
	left_v.custom_minimum_size = Vector2(390.0, 520.0)
	left_v.add_theme_constant_override("separation", 8)
	cols.add_child(left_v)

	left_v.add_child(_ink_lbl("◆ 选择已获丹方：", 19, Color("#5A3320")))
	for rid: String in CampaignState.unlocked_recipes:
		var rdef: Dictionary = DataDB.get_recipe(rid)
		var qb: bool = CampaignState.quick_brew_recipes.has(rid)
		var rb: Button = Button.new()
		rb.focus_mode = Control.FOCUS_NONE
		rb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		rb.text = "%s%s%s" % ["▶ " if rid == selected_rid else "", DataDB.loc(str(rdef.get("name_key", rid))), " ★速炼" if qb else ""]
		rb.pressed.connect(func() -> void: open_alchemy_furnace(rid))
		left_v.add_child(rb)

	var right_box: PanelContainer = PanelContainer.new()
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.13, 0.12, 0.11, 0.96), UIThemeBuilder.COL_BRONZE_GOLD, 2, 6))
	cols.add_child(right_box)

	var rv: VBoxContainer = VBoxContainer.new()
	rv.add_theme_constant_override("separation", 12)
	right_box.add_child(rv)

	var rdef_cur: Dictionary = DataDB.get_recipe(selected_rid)
	if rdef_cur.is_empty():
		return

	var rtitle: Label = Label.new()
	rtitle.text = "【%s】" % DataDB.loc(str(rdef_cur.get("name_key", selected_rid)))
	rtitle.add_theme_font_size_override("font_size", 22)
	rtitle.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD)
	rv.add_child(rtitle)

	var rdesc: Label = Label.new()
	rdesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rdesc.text = DataDB.loc(str(rdef_cur.get("desc_key", "")))
	rv.add_child(rdesc)

	var max_craftable: int = 99
	var ing_lines: PackedStringArray = PackedStringArray(["所需灵草药引："])
	for raw_ing: Variant in (rdef_cur.get("ingredients", []) as Array):
		if raw_ing is Dictionary:
			var ing: Dictionary = raw_ing as Dictionary
			var mid: String = str(ing.get("item_id", ""))
			var need: int = maxi(1, int(ing.get("count", 1)))
			var have: int = CampaignState.get_item_count(mid)
			max_craftable = mini(max_craftable, int(floor(float(have) / float(need))))
			ing_lines.append("  · %s：需 %d 株（行囊现有 %d 株）" % [
				DataDB.loc(str(DataDB.get_any_item_or_equip(mid).get("name_key", mid))), need, have
			])
	var ing_lbl: Label = Label.new()
	ing_lbl.text = "\n".join(ing_lines)
	ing_lbl.add_theme_color_override("font_color", Color("#9EE0C4") if max_craftable >= 1 else Color("#F09A7E"))
	rv.add_child(ing_lbl)

	var start_fire_btn: Button = Button.new()
	start_fire_btn.text = "起火开炉 · 15秒文武控火炼丹（炼出无瑕丹纹永久解锁速炼！）"
	start_fire_btn.focus_mode = Control.FOCUS_NONE
	start_fire_btn.disabled = max_craftable <= 0
	start_fire_btn.pressed.connect(func() -> void: _start_15s_fire_minigame(selected_rid))
	rv.add_child(start_fire_btn)

	if CampaignState.quick_brew_recipes.has(selected_rid):
		var qb_box: HBoxContainer = HBoxContainer.new()
		qb_box.add_theme_constant_override("separation", 12)
		rv.add_child(qb_box)

		var slider: HSlider = HSlider.new()
		slider.min_value = 1.0
		slider.max_value = float(maxi(1, max_craftable))
		slider.step = 1.0
		slider.value = 1.0
		slider.custom_minimum_size = Vector2(220.0, 32.0)
		qb_box.add_child(slider)

		var qb_btn: Button = Button.new()
		qb_btn.text = "一键完美速炼 ×1 枚无瑕极品"
		qb_btn.focus_mode = Control.FOCUS_NONE
		qb_btn.disabled = max_craftable <= 0
		slider.value_changed.connect(func(val: float) -> void:
			qb_btn.text = "一键完美速炼 ×%d 枚无瑕极品" % int(val)
		)
		qb_btn.pressed.connect(func() -> void:
			var batch: int = clampi(int(slider.value), 1, max_craftable)
			for _k: int in range(batch):
				_consume_recipe_ingredients(rdef_cur)
			CampaignState.add_item(str(rdef_cur.get("flawless_item_id", "")), batch, false)
			if audio_director != null:
				audio_director.play_sfx("sfx_alchemy_success", AudioDirector.TIER_A, true)
			open_alchemy_furnace(selected_rid)
		)
		qb_box.add_child(qb_btn)


func _start_15s_fire_minigame(recipe_id: String) -> void:
	var rdef: Dictionary = DataDB.get_recipe(recipe_id)
	if not _consume_recipe_ingredients(rdef):
		return
	_open_base("alchemy_active", Vector2(960.0, 520.0))
	_add_header("【丹炉控火中】使用 A / D 键、鼠标滚轮或下方按钮调节文武火候！")

	_brew_recipe_id = recipe_id
	_brew_targets = (rdef.get("fire_targets", [0.35, 0.65, 0.40]) as Array).duplicate()
	_brew_recorded.clear()
	_brew_elapsed = 0.0
	_brew_heat = 0.50
	_brew_running = true

	_brew_stage_lbl = _ink_lbl("第一候（0.0s / 15.0s）· 温炉引药", 22, Color("#5A3320"))
	_card_vbox.add_child(_brew_stage_lbl)

	_brew_target_lbl = _ink_lbl("", 18, Color("#23483E"))
	_card_vbox.add_child(_brew_target_lbl)

	var gauge_bg: ColorRect = ColorRect.new()
	gauge_bg.custom_minimum_size = Vector2(860.0, 44.0)
	gauge_bg.color = Color(0.14, 0.12, 0.11, 0.96)
	_card_vbox.add_child(gauge_bg)

	_brew_target_marker = ColorRect.new()
	_brew_target_marker.size = Vector2(120.0, 44.0)
	_brew_target_marker.color = Color(0.35, 0.78, 0.56, 0.48)
	gauge_bg.add_child(_brew_target_marker)

	_brew_heat_bar = ColorRect.new()
	_brew_heat_bar.size = Vector2(14.0, 48.0)
	_brew_heat_bar.position = Vector2(420.0, -2.0)
	_brew_heat_bar.color = UIThemeBuilder.COL_CINNABAR_RED
	gauge_bg.add_child(_brew_heat_bar)

	var ctrl_hb: HBoxContainer = HBoxContainer.new()
	ctrl_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	ctrl_hb.add_theme_constant_override("separation", 24)
	_card_vbox.add_child(ctrl_hb)

	var wen_b: Button = Button.new()
	wen_b.text = "◀ 敛气文火 (A)"
	wen_b.focus_mode = Control.FOCUS_NONE
	wen_b.pressed.connect(func() -> void: _adjust_brew_heat(-0.08))
	ctrl_hb.add_child(wen_b)

	var wu_b: Button = Button.new()
	wu_b.text = "催焰武火 (D) ▶"
	wu_b.focus_mode = Control.FOCUS_NONE
	wu_b.pressed.connect(func() -> void: _adjust_brew_heat(0.08))
	ctrl_hb.add_child(wu_b)


func _adjust_brew_heat(delta_h: float) -> void:
	_brew_heat = clampf(_brew_heat + delta_h, 0.0, 1.0)
	if audio_director != null:
		audio_director.play_sfx("sfx_alchemy_fire", AudioDirector.TIER_B, true)


func _process(delta: float) -> void:
	if not visible or not _brew_running:
		return

	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		_brew_heat = clampf(_brew_heat - delta * 0.55, 0.0, 1.0)
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		_brew_heat = clampf(_brew_heat + delta * 0.55, 0.0, 1.0)
	# 炉火轻微自然波动
	_brew_heat = clampf(_brew_heat + sin(_brew_elapsed * 2.8) * delta * 0.12, 0.0, 1.0)

	var prev_stage: int = int(floor(_brew_elapsed / 5.0))
	_brew_elapsed += delta
	var cur_stage: int = mini(2, int(floor(_brew_elapsed / 5.0)))

	if cur_stage > prev_stage and _brew_recorded.size() < 3:
		_brew_recorded.append(_brew_heat)
		if audio_director != null:
			audio_director.play_sfx("sfx_alchemy_fire", AudioDirector.TIER_A, true)

	if _brew_elapsed >= 15.0:
		while _brew_recorded.size() < 3:
			_brew_recorded.append(_brew_heat)
		_brew_running = false
		_finish_15s_fire_minigame()
		return

	var target_v: float = float(_brew_targets[cur_stage])
	var stage_names: Array[String] = ["第一候 · 文火融草", "第二候 · 催灵化液", "第三候 · 武收丹纹"]
	_brew_stage_lbl.text = "%s（%.1fs / 15.0s）" % [stage_names[cur_stage], _brew_elapsed]
	_brew_target_lbl.text = "请将赤红火标保持在翠玉理想温区内（当前火候 %d%% / 理想 %d%%）" % [int(_brew_heat * 100.0), int(target_v * 100.0)]
	_brew_target_marker.position.x = clampf(target_v * 860.0 - 60.0, 0.0, 740.0)
	_brew_heat_bar.position.x = clampf(_brew_heat * 860.0 - 7.0, 0.0, 846.0)


func _finish_15s_fire_minigame() -> void:
	var rdef: Dictionary = DataDB.get_recipe(_brew_recipe_id)
	var res: Dictionary = EconomyRules.evaluate_first_brew_fire(_brew_targets, _brew_recorded, rdef)
	var out_id: String = str(res.get("output_item_id", ""))
	CampaignState.add_item(out_id, 1, false)
	if bool(res.get("unlock_quick_brew", false)) and not CampaignState.quick_brew_recipes.has(_brew_recipe_id):
		CampaignState.quick_brew_recipes.append(_brew_recipe_id)
	if audio_director != null:
		audio_director.play_sfx("sfx_alchemy_success", AudioDirector.TIER_A, true)
	NotifyHub.push_explore_slip("丹炉出丹", tr(str(res.get("result_key", "UI_BREW_STANDARD"))), "alchemy")
	open_alchemy_furnace(_brew_recipe_id)


func _consume_recipe_ingredients(rdef: Dictionary) -> bool:
	var ings: Array = rdef.get("ingredients", []) as Array
	for raw_i: Variant in ings:
		if raw_i is Dictionary:
			var ing: Dictionary = raw_i as Dictionary
			if CampaignState.get_item_count(str(ing.get("item_id", ""))) < int(ing.get("count", 1)):
				return false
	for raw_i2: Variant in ings:
		if raw_i2 is Dictionary:
			var ing2: Dictionary = raw_i2 as Dictionary
			CampaignState.remove_item(str(ing2.get("item_id", "")), int(ing2.get("count", 1)))
	return true


## ==================== 2. 药肆商店与散修小地摊（含掌眼鉴宝与二次确认） ====================
func open_shop_modal(shop_id: String, confirm_item_id: String = "") -> void:
	_open_base("shop", Vector2(1280.0, 690.0))
	var sdef: Dictionary = DataDB.get_shop(shop_id)
	var is_peddler: bool = bool(sdef.get("is_peddler_stall", false))
	var fac_id: String = str(sdef.get("faction_id", ""))
	var rep_pts: int = int(CampaignState.faction_reputation.get(fac_id, 0)) if fac_id != "" else 0

	_add_header("【%s】随身灵石：%d 枚" % [DataDB.loc(str(sdef.get("name_key", shop_id))), CampaignState.spirit_stones])

	var intro_box: PanelContainer = PanelContainer.new()
	intro_box.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.15, 0.13, 0.11, 0.94), UIThemeBuilder.COL_BRONZE_DIM, 1, 5))
	_card_vbox.add_child(intro_box)
	var intro_lbl: Label = Label.new()
	intro_lbl.text = (
		"  ◆ 山野散修席地摆摊，旧物真赝混杂。可将鼠标移至器物上逐件掌眼端详，留心器物灵韵……  "
		if is_peddler
		else "  ◆ 济世药庐外院药肆，专售青岚灵草、丹药与避瘴灵符；同道声望深厚者可获药资减免。  "
	)
	intro_lbl.add_theme_font_size_override("font_size", 17)
	intro_lbl.add_theme_color_override("font_color", Color("#E6DCC8"))
	intro_box.add_child(intro_lbl)

	if confirm_item_id != "":
		var c_idef: Dictionary = DataDB.get_any_item_or_equip(confirm_item_id)
		var c_price: int = EconomyRules.compute_buy_price(int(c_idef.get("buy_price", 50)), rep_pts)
		var cpanel: PanelContainer = PanelContainer.new()
		cpanel.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.18, 0.13, 0.10, 0.98), UIThemeBuilder.COL_BRONZE_GOLD, 2, 6))
		_card_vbox.add_child(cpanel)
		var chb: HBoxContainer = HBoxContainer.new()
		chb.add_theme_constant_override("separation", 16)
		cpanel.add_child(chb)
		var clbl: Label = Label.new()
		clbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		clbl.text = "确认耗费 %d 枚灵石购入【%s】？" % [c_price, DataDB.loc(str(c_idef.get("name_key", confirm_item_id)))]
		chb.add_child(clbl)
		var yes_b: Button = Button.new()
		yes_b.text = tr("UI_BTN_CONFIRM")
		yes_b.focus_mode = Control.FOCUS_NONE
		yes_b.pressed.connect(func() -> void:
			_execute_shop_purchase(shop_id, confirm_item_id, c_price)
		)
		chb.add_child(yes_b)
		var no_b: Button = Button.new()
		no_b.text = tr("UI_BTN_CANCEL")
		no_b.focus_mode = Control.FOCUS_NONE
		no_b.pressed.connect(func() -> void: open_shop_modal(shop_id, ""))
		chb.add_child(no_b)

	var cols: HBoxContainer = HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 18)
	_card_vbox.add_child(cols)

	# 底部【掌眼端详 · 器物铭鉴】详情栏（消除面板下半截留白，承载含蓄鉴宝体验）
	var inspect_panel: PanelContainer = PanelContainer.new()
	inspect_panel.custom_minimum_size = Vector2(1060.0, 108.0)
	inspect_panel.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.12, 0.11, 0.10, 0.97), UIThemeBuilder.COL_BRONZE_GOLD, 2, 6))
	_card_vbox.add_child(inspect_panel)

	var inspect_hb: HBoxContainer = HBoxContainer.new()
	inspect_hb.add_theme_constant_override("separation", 16)
	inspect_panel.add_child(inspect_hb)

	var inspect_icon_frame: PanelContainer = _make_icon_slot("", 64.0)
	inspect_hb.add_child(inspect_icon_frame)
	var inspect_icon_rect: TextureRect = inspect_icon_frame.get_child(0) as TextureRect

	var inspect_vb: VBoxContainer = VBoxContainer.new()
	inspect_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspect_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	inspect_vb.add_theme_constant_override("separation", 4)
	inspect_hb.add_child(inspect_vb)

	var inspect_title: Label = Label.new()
	inspect_title.add_theme_font_size_override("font_size", 19)
	inspect_title.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD)
	inspect_vb.add_child(inspect_title)

	var inspect_desc: Label = Label.new()
	inspect_desc.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	inspect_desc.add_theme_font_size_override("font_size", 16)
	inspect_desc.add_theme_color_override("font_color", UIThemeBuilder.COL_XUAN_WARM)
	inspect_vb.add_child(inspect_desc)

	var inspect_sense: Label = Label.new()
	inspect_sense.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	inspect_sense.add_theme_font_size_override("font_size", 16)
	inspect_vb.add_child(inspect_sense)

	var last_hum_id: Array[String] = [""]
	var update_inspector: Callable = func(target_id: String) -> void:
		var tdef: Dictionary = DataDB.get_any_item_or_equip(target_id)
		if tdef.is_empty():
			return
		var icon_p: String = str(tdef.get("icon", ""))
		inspect_icon_rect.texture = (load(icon_p) as Texture2D) if (icon_p != "" and ResourceLoader.exists(icon_p)) else null
		var have_n: int = CampaignState.get_item_count(target_id)
		inspect_title.text = "【%s】  ·  行囊现存：%d" % [DataDB.loc(str(tdef.get("name_key", target_id))), have_n]
		inspect_desc.text = DataDB.loc(str(tdef.get("desc_key", "")))
		if is_peddler and str(tdef.get("category", "")) == "curio":
			if bool(tdef.get("sword_box_resonance", false)):
				inspect_sense.text = "❖ 掌眼细观：指尖掠过铁锈断口的一瞬，背上【断玉剑匣】似隔着衣衫传来一丝极微弱的温热颤鸣……"
				inspect_sense.add_theme_color_override("font_color", Color("#8FE3C0"))
				if audio_director != null and last_hum_id[0] != target_id:
					last_hum_id[0] = target_id
					audio_director.play_sfx("sfx_sword_box_hum", AudioDirector.TIER_B, true)
			else:
				last_hum_id[0] = target_id
				inspect_sense.text = "· 掌眼细观：器表灵气早已涣散驳杂，怀中剑匣亦毫无动静，多半只是寻常山野旧物。"
				inspect_sense.add_theme_color_override("font_color", Color("#9E9589"))
		else:
			inspect_sense.text = ""

	# 左栏：购入货架（统一乌木错金条目卡 + 48x48 工笔图标，绝不剧透绿框）
	var left_col: VBoxContainer = VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 8)
	cols.add_child(left_col)
	left_col.add_child(_ink_lbl("◆ 摊席旧物（悬停掌眼鉴宝）：" if is_peddler else "◆ 药庐丹草陈列：", 19, Color("#5A3320")))

	var buy_scroll: ScrollContainer = ScrollContainer.new()
	buy_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_child(buy_scroll)
	var buy_v: VBoxContainer = VBoxContainer.new()
	buy_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy_v.add_theme_constant_override("separation", 8)
	buy_scroll.add_child(buy_v)

	var first_inspect_id: String = ""
	for raw_sid: Variant in (sdef.get("stock", []) as Array):
		var sid: String = str(raw_sid)
		if sid == "item_stall_sword_shard" and bool(CampaignState.world_flags.get("peddler_gem_bought", false)):
			continue
		if first_inspect_id == "":
			first_inspect_id = sid
		var idef: Dictionary = DataDB.get_any_item_or_equip(sid)
		var price: int = EconomyRules.compute_buy_price(int(idef.get("buy_price", 30)), rep_pts)
		var owned_cnt: int = CampaignState.get_item_count(sid)

		var row_p: PanelContainer = PanelContainer.new()
		row_p.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.14, 0.13, 0.12, 0.96), UIThemeBuilder.COL_BRONZE_DIM, 1, 5))
		row_p.mouse_entered.connect(func() -> void: update_inspector.call(sid))
		row_p.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
				update_inspector.call(sid)
		)
		buy_v.add_child(row_p)

		var rhb: HBoxContainer = HBoxContainer.new()
		rhb.mouse_filter = Control.MOUSE_FILTER_PASS
		rhb.add_theme_constant_override("separation", 12)
		row_p.add_child(rhb)

		rhb.add_child(_make_icon_slot(str(idef.get("icon", "")), 48.0))

		var ilbl: Label = Label.new()
		ilbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ilbl.custom_minimum_size = Vector2(455.0, 0.0)
		ilbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		var owned_tag: String = ("  [已有×%d]" % owned_cnt) if owned_cnt > 0 else ""
		ilbl.text = "【%s】· %d 灵石%s\n%s" % [
			DataDB.loc(str(idef.get("name_key", sid))),
			price,
			owned_tag,
			DataDB.loc(str(idef.get("desc_key", "")))
		]
		ilbl.add_theme_font_size_override("font_size", 16)
		ilbl.add_theme_color_override("font_color", UIThemeBuilder.COL_XUAN_WARM)
		rhb.add_child(ilbl)

		var buy_b: Button = Button.new()
		buy_b.text = "购入"
		buy_b.focus_mode = Control.FOCUS_NONE
		buy_b.custom_minimum_size = Vector2(78.0, 40.0)
		buy_b.disabled = CampaignState.spirit_stones < price
		buy_b.mouse_entered.connect(func() -> void: update_inspector.call(sid))
		buy_b.pressed.connect(func() -> void:
			if price >= 60:
				open_shop_modal(shop_id, sid)
			else:
				_execute_shop_purchase(shop_id, sid, price)
		)
		rhb.add_child(buy_b)

	# 右栏：行囊寻常丹草寄售（同样带 48x48 工笔图标与乌木底卡，自动过滤锁护珍品）
	var right_col: VBoxContainer = VBoxContainer.new()
	right_col.custom_minimum_size = Vector2(465.0, 340.0)
	right_col.add_theme_constant_override("separation", 8)
	cols.add_child(right_col)
	right_col.add_child(_ink_lbl("◆ 行囊寄售（坊市折价收兑寻常丹草）：", 19, Color("#5A3320")))

	var sell_scroll: ScrollContainer = ScrollContainer.new()
	sell_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_child(sell_scroll)
	var sell_v: VBoxContainer = VBoxContainer.new()
	sell_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_v.add_theme_constant_override("separation", 8)
	sell_scroll.add_child(sell_v)

	var sellable_shown: int = 0
	for entry: Dictionary in CampaignState.inventory:
		var iid: String = str(entry.get("id", ""))
		var cnt: int = int(entry.get("count", 0))
		var idef2: Dictionary = DataDB.get_any_item_or_equip(iid)
		if bool(idef2.get("unsellable", false)):
			continue
		var cat2: String = str(idef2.get("category", ""))
		if cat2 == "quest" or cat2 == "storage_pouch":
			continue
		var s_price: int = EconomyRules.compute_sell_price(int(idef2.get("buy_price", 20)), int(idef2.get("sell_price", -1)))
		if s_price <= 0 or int(idef2.get("buy_price", 0)) <= 0:
			continue
		sellable_shown += 1

		var s_card: PanelContainer = PanelContainer.new()
		s_card.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.15, 0.14, 0.12, 0.94), UIThemeBuilder.COL_BRONZE_DIM, 1, 5))
		s_card.mouse_entered.connect(func() -> void: update_inspector.call(iid))
		sell_v.add_child(s_card)

		var shb: HBoxContainer = HBoxContainer.new()
		shb.add_theme_constant_override("separation", 10)
		s_card.add_child(shb)

		shb.add_child(_make_icon_slot(str(idef2.get("icon", "")), 44.0))

		var slbl: Label = Label.new()
		slbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slbl.text = "%s ×%d\n收兑价：+%d 灵石" % [DataDB.loc(str(idef2.get("name_key", iid))), cnt, s_price]
		slbl.add_theme_font_size_override("font_size", 16)
		slbl.add_theme_color_override("font_color", UIThemeBuilder.COL_XUAN_WARM)
		shb.add_child(slbl)

		var sb_btn: Button = Button.new()
		sb_btn.text = "售出 1"
		sb_btn.focus_mode = Control.FOCUS_NONE
		sb_btn.custom_minimum_size = Vector2(82.0, 38.0)
		sb_btn.mouse_entered.connect(func() -> void: update_inspector.call(iid))
		sb_btn.pressed.connect(func() -> void:
			if CampaignState.remove_item(iid, 1):
				CampaignState.add_spirit_stones(s_price, true)
				open_shop_modal(shop_id, "")
		)
		shb.add_child(sb_btn)

	if sellable_shown == 0:
		sell_v.add_child(_ink_lbl("（行囊中暂无可寄售的寻常灵草丹散）", 16, Color("#5F5346")))
	right_col.add_child(_ink_lbl("注：奇物、洗髓灵露与秘藏信物已自动锁护，免遭误售。", 16, Color("#4D4236")))

	if first_inspect_id != "":
		update_inspector.call(first_inspect_id)


func _make_icon_slot(icon_path: String, box_px: float) -> PanelContainer:
	var frame: PanelContainer = PanelContainer.new()
	frame.custom_minimum_size = Vector2(box_px, box_px)
	var sb: StyleBoxFlat = UIThemeBuilder.make_ebony_box(Color(0.09, 0.08, 0.08, 0.98), UIThemeBuilder.COL_BRONZE_DIM, 1, 4)
	sb.content_margin_left = 3.0
	sb.content_margin_right = 3.0
	sb.content_margin_top = 3.0
	sb.content_margin_bottom = 3.0
	frame.add_theme_stylebox_override("panel", sb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tr_icon: TextureRect = TextureRect.new()
	tr_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon_path != "" and ResourceLoader.exists(icon_path):
		tr_icon.texture = load(icon_path) as Texture2D
	frame.add_child(tr_icon)
	return frame


func _execute_shop_purchase(shop_id: String, item_id: String, price: int) -> void:
	if not CampaignState.add_spirit_stones(-price, true):
		return
	CampaignState.add_item(item_id, 1, false)
	if item_id == "item_stall_sword_shard":
		CampaignState.world_flags["peddler_gem_bought"] = true
		CampaignState.quest_states["q_side_yaolu_spy"] = "stage_ambush_clue"
		CampaignState.unlock_clue("clue_peddler_shard")
		peddler_treasure_bought.emit()
	open_shop_modal(shop_id, "")


## ==================== 3. 引灵石碑（休整回满 + 篝火夜话 + 石碑传送） ====================
func open_stele_modal(stele_id: String, stele_title: String) -> void:
	CampaignState.rest_at_stele(stele_id)
	SaveManager.save_rolling_auto()
	if audio_director != null:
		audio_director.play_sfx("sfx_stele_activate", AudioDirector.TIER_A)

	_open_base("stele", Vector2(920.0, 560.0))
	_add_header("【引灵石碑 · %s】全队气血真元已回满、经脉暗伤已涤除！" % stele_title)

	_card_vbox.add_child(_ink_lbl("◆ 篝火夜话（提升同道五阶词牌羁绊，解锁双人合击）：", 20, Color("#5A3320")))
	var talks: Array[Array] = [
		["night_talk_1", "dlg_night_talk_1", "夜话一 · 温药护脉与故村血誓（沈清禾同在时可叙 · 解锁【青莲引剑】）", CampaignState.recruited_order.has("shen_qinghe")],
		["night_talk_2", "dlg_night_talk_2", "夜话二 · 青云封卷之疑（裴照入阵后可叙）", CampaignState.recruited_order.has("pei_zhao")],
		["night_talk_3", "dlg_night_talk_3", "夜话三 · 灵枢战前同心（深入苍木古窟后可叙 · 赠无瑕聚气丸）", CampaignState.current_zone_id == "cangmu_cave"],
	]
	for tmeta: Array in talks:
		var tid: String = str(tmeta[0])
		var dlg_id: String = str(tmeta[1])
		var tlabel: String = str(tmeta[2])
		var cond: bool = bool(tmeta[3])
		var seen: bool = CampaignState.viewed_night_talks.has(tid)
		var tb: Button = Button.new()
		tb.focus_mode = Control.FOCUS_NONE
		tb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tb.text = "%s%s" % ["[已叙·可重温] " if seen else "★ ", tlabel]
		tb.disabled = not cond
		tb.pressed.connect(func() -> void:
			close_modal()
			night_talk_selected.emit(dlg_id)
		)
		_card_vbox.add_child(tb)

	_card_vbox.add_child(_ink_lbl("◆ 引灵石碑地脉传送（在已点亮的石碑间瞬息往返）：", 20, Color("#23483E")))
	var all_steles: Array[Array] = [
		["stele_tingyu_gate", "tingyu_town", "stele_tingyu_gate", "听雨镇 · 北驿口引灵石碑"],
		["stele_temple_courtyard", "qinglan_pass", "stele_temple_courtyard", "青岚山道 · 破庙前庭石碑"],
		["stele_cave_mid", "cangmu_cave", "stele_cave_mid", "苍木古窟 · 中枢回环门石碑"],
		["stele_wolf_altar", "cangmu_cave", "stele_wolf_altar", "苍木古窟 · 灵枢祭坛门前石碑"],
	]
	for smeta: Array in all_steles:
		var sid: String = str(smeta[0])
		var szone: String = str(smeta[1])
		var sspawn: String = str(smeta[2])
		var sname: String = str(smeta[3])
		if not CampaignState.unlocked_steles.has(sid):
			continue
		var sb: Button = Button.new()
		sb.focus_mode = Control.FOCUS_NONE
		sb.text = ("● 当前所在 · " if sid == stele_id else "▸ 传送前往 · ") + sname
		sb.disabled = (sid == stele_id)
		sb.pressed.connect(func() -> void:
			close_modal()
			stele_teleport_selected.emit(szone, sspawn, sid)
		)
		_card_vbox.add_child(sb)


## ==================== 4. 青岚境手绘舆图（M 键，淡墨线索范围圈） ====================
func open_world_map_modal() -> void:
	_open_base("map", Vector2(1080.0, 640.0))
	_add_header("【青岚境 · 山水风物舆图】淡墨圆圈为《问道手札》线索大致范围（无自动寻路）")

	var canvas: Control = Control.new()
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.draw.connect(func() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, canvas.size)
		canvas.draw_rect(r, Color("#CEC3B0"), true)
		canvas.draw_rect(r, Color("#6E5233"), false, 3.0)
		var font: Font = UIThemeBuilder.get_bold_font()
		if font == null:
			font = ThemeDB.fallback_font

		var zones: Array[Dictionary] = [
			{"id": "tingyu_town", "pos": Vector2(210.0, 340.0), "title": "① 听雨镇 & 济世药庐", "sub": "茶寮 · 药肆丹炉 · 散修地摊"},
			{"id": "qinglan_pass", "pos": Vector2(520.0, 240.0), "title": "② 风雨山道 & 青岚破庙", "sub": "巡逻狼群 · 救兽契宠 · 竹林劫修 · 悬崖石匣"},
			{"id": "cangmu_cave", "pos": Vector2(835.0, 165.0), "title": "③ 苍木灵枢古窟", "sub": "火焚毒棘 · 水净瘴池 · 敛息偷草 · 雾隐狼王"},
		]
		canvas.draw_dashed_line(zones[0]["pos"] as Vector2, zones[1]["pos"] as Vector2, Color("#4A3D31"), 3.0, 10.0)
		canvas.draw_dashed_line(zones[1]["pos"] as Vector2, zones[2]["pos"] as Vector2, Color("#4A3D31"), 3.0, 10.0)

		for zd: Dictionary in zones:
			var zp: Vector2 = zd["pos"] as Vector2
			var zid: String = str(zd["id"])
			var is_cur: bool = (CampaignState.current_zone_id == zid)
			canvas.draw_circle(zp, 68.0, Color("#23483E") if is_cur else Color("#8C7A62"))
			canvas.draw_arc(zp, 74.0, 0.0, TAU, 36, UIThemeBuilder.COL_BRONZE_GOLD if is_cur else Color("#3E352D"), 3.0)
			canvas.draw_string(font, zp + Vector2(-95.0, 98.0), str(zd["title"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("#221B16"))
			canvas.draw_string(font, zp + Vector2(-105.0, 122.0), str(zd["sub"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#4D4238"))
			if is_cur:
				canvas.draw_string(font, zp + Vector2(-42.0, 6.0), "【当前所在】", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#FCE49C"))

		# 绘制《问道手札》淡墨搜索范围圈
		var main_st: String = str(CampaignState.quest_states.get("q_main_ch01", ""))
		var hint_pt: Vector2 = zones[0]["pos"] as Vector2
		if main_st == "stage_go_temple":
			hint_pt = zones[1]["pos"] as Vector2
		elif main_st.begins_with("stage_enter") or main_st.begins_with("stage_wolf"):
			hint_pt = zones[2]["pos"] as Vector2
		canvas.draw_arc(hint_pt, 96.0, 0.0, TAU, 40, Color(0.72, 0.24, 0.18, 0.65), 3.0)
		canvas.draw_string(font, Vector2(40.0, 48.0), "朱砂淡墨圈：当前主脉线索指向方位", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#8E2822"))
	)
	_card_vbox.add_child(canvas)


## ==================== 5. 存档读档面板 & 4 总线音频/无障碍/改键设置 ====================
func open_save_load_modal(allow_save: bool = true) -> void:
	_open_base("save_load", Vector2(1080.0, 720.0))
	var check_save: Dictionary = SaveManager.can_save_now()
	var can_write: bool = allow_save and bool(check_save.get("ok", false))
	_add_header("【道卷留存与读取】SHA-256 信封校验 · .tmp/.bak 原子落盘 · 损坏零覆盖保护")

	if allow_save and not can_write:
		_card_vbox.add_child(_ink_lbl("提示：%s" % tr(str(check_save.get("reason_key", "MSG_SAVE_COMBAT_BLOCKED"))), 18, UIThemeBuilder.COL_CINNABAR_RED))

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card_vbox.add_child(scroll)

	var list_v: VBoxContainer = VBoxContainer.new()
	list_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_v.add_theme_constant_override("separation", 8)
	scroll.add_child(list_v)

	for entry: Dictionary in SaveManager.list_all_slots():
		var sid: String = str(entry.get("slot_id", ""))
		var is_auto: bool = bool(entry.get("is_auto", false))
		var status: String = str(entry.get("status", "empty"))

		var row_p: PanelContainer = PanelContainer.new()
		row_p.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.14, 0.13, 0.12, 0.95), UIThemeBuilder.COL_BRONZE_DIM, 1, 4))
		list_v.add_child(row_p)

		var hb: HBoxContainer = HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		row_p.add_child(hb)

		var desc_txt: String = "[自动槽 %s] " % sid if is_auto else "[手动槽 %s] " % sid
		if status == "empty":
			desc_txt += "—— 空置道卷 ——"
		elif status == "corrupted":
			desc_txt += "【校验异常 · 原档已受保护未覆盖】" + ("（存在可用 .bak 备份）" if bool(entry.get("has_backup", false)) else "")
		else:
			var mins: int = int(floor(float(int(entry.get("playtime_sec", 0))) / 60.0))
			desc_txt += "%s · %s · 灵石 %d · 历时 %d 分钟 (%s)" % [
				str(entry.get("location", "")),
				str(entry.get("realm", "")),
				int(entry.get("spirit_stones", 0)),
				mins,
				str(entry.get("saved_at_utc", ""))
			]

		var slbl: Label = Label.new()
		slbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slbl.text = desc_txt
		slbl.add_theme_font_size_override("font_size", 16)
		slbl.add_theme_color_override("font_color", UIThemeBuilder.COL_CINNABAR_RED if status == "corrupted" else UIThemeBuilder.COL_XUAN_WARM)
		hb.add_child(slbl)

		if not is_auto and allow_save:
			var num_idx: int = int(sid.trim_prefix("slot_"))
			var save_b: Button = Button.new()
			save_b.text = "写入此卷"
			save_b.focus_mode = Control.FOCUS_NONE
			save_b.disabled = (not can_write) or (status == "corrupted")
			save_b.pressed.connect(func() -> void:
				SaveManager.save_manual_slot(num_idx)
				open_save_load_modal(allow_save)
			)
			hb.add_child(save_b)

		var load_b: Button = Button.new()
		load_b.text = "读取"
		load_b.focus_mode = Control.FOCUS_NONE
		load_b.disabled = (status == "empty")
		load_b.pressed.connect(func() -> void:
			var lres: Dictionary = SaveManager.load_slot(sid, false)
			if bool(lres.get("ok", false)):
				close_modal()
				save_loaded_reload_zone.emit()
		)
		hb.add_child(load_b)


func open_settings_modal() -> void:
	_open_base("settings", Vector2(1140.0, 740.0))
	_add_header("【器物与音律设置】4 总线独立持久化 · 无障碍双编码 · 纯 PC 键鼠映射")

	var cols: HBoxContainer = HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 20)
	_card_vbox.add_child(cols)

	# 左栏：4 音频总线 + 难度 + 舒适无障碍
	var lv: VBoxContainer = VBoxContainer.new()
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_theme_constant_override("separation", 10)
	cols.add_child(lv)

	lv.add_child(_ink_lbl("◆ 四总线独立音量控制（实时写入 user://settings.cfg）：", 19, Color("#5A3320")))
	_add_slider_row(lv, "主音量总控", SaveManager.master_volume, func(v: float) -> void:
		SaveManager.master_volume = v
		SaveManager.save_settings()
	)
	_add_slider_row(lv, "背景民乐 (BGM)", SaveManager.bgm_volume, func(v: float) -> void:
		SaveManager.bgm_volume = v
		SaveManager.save_settings()
	)
	_add_slider_row(lv, "斗法音效 (Combat SFX)", SaveManager.combat_sfx_volume, func(v: float) -> void:
		SaveManager.combat_sfx_volume = v
		SaveManager.save_settings()
	)
	_add_slider_row(lv, "环境与界面 (Ambient & UI)", SaveManager.ambient_ui_volume, func(v: float) -> void:
		SaveManager.ambient_ui_volume = v
		SaveManager.save_settings()
	)

	var mute_cb: CheckBox = CheckBox.new()
	mute_cb.text = "全部声音总静音"
	mute_cb.button_pressed = SaveManager.master_muted
	mute_cb.focus_mode = Control.FOCUS_NONE
	mute_cb.add_theme_color_override("font_color", UIThemeBuilder.COL_INK_DARK)
	mute_cb.toggled.connect(func(on: bool) -> void:
		SaveManager.master_muted = on
		SaveManager.save_settings()
	)
	lv.add_child(mute_cb)

	var bg_mute_cb: CheckBox = CheckBox.new()
	bg_mute_cb.text = "窗口失焦切后台时自动静音"
	bg_mute_cb.button_pressed = SaveManager.mute_on_unfocus
	bg_mute_cb.focus_mode = Control.FOCUS_NONE
	bg_mute_cb.add_theme_color_override("font_color", UIThemeBuilder.COL_INK_DARK)
	bg_mute_cb.toggled.connect(func(on: bool) -> void:
		SaveManager.mute_on_unfocus = on
		SaveManager.save_settings()
	)
	lv.add_child(bg_mute_cb)

	lv.add_child(_ink_lbl("◆ 无障碍与斗法难度（随时可调，不影响真结局资格）：", 19, Color("#5A3320")))
	_add_slider_row(lv, "受击震屏强度", SaveManager.screen_shake_pct, func(v: float) -> void:
		SaveManager.screen_shake_pct = v
		SaveManager.save_settings()
	)

	var rm_cb: CheckBox = CheckBox.new()
	rm_cb.text = "减弱动态效果（Reduced Motion）"
	rm_cb.button_pressed = SaveManager.reduced_motion
	rm_cb.focus_mode = Control.FOCUS_NONE
	rm_cb.add_theme_color_override("font_color", UIThemeBuilder.COL_INK_DARK)
	rm_cb.toggled.connect(func(on: bool) -> void:
		SaveManager.reduced_motion = on
		SaveManager.save_settings()
	)
	lv.add_child(rm_cb)

	var diff_hb: HBoxContainer = HBoxContainer.new()
	diff_hb.add_theme_constant_override("separation", 8)
	lv.add_child(diff_hb)
	for dpair: Array in [["ask_heart", "问心"], ["cultivation", "修行(标准)"], ["tribulation", "渡劫"]]:
		var dk: String = str(dpair[0])
		var db: Button = Button.new()
		db.focus_mode = Control.FOCUS_NONE
		db.text = ("★ " if CampaignState.difficulty == dk else "") + str(dpair[1])
		db.pressed.connect(func() -> void:
			CampaignState.difficulty = dk
			open_settings_modal()
		)
		diff_hb.add_child(db)

	if not is_standalone_on_title:
		var title_btn: Button = Button.new()
		title_btn.text = "返回标题主画卷"
		title_btn.focus_mode = Control.FOCUS_NONE
		title_btn.pressed.connect(func() -> void:
			close_modal()
			return_to_title_requested.emit()
		)
		lv.add_child(title_btn)

	# 右栏：纯 PC 键鼠映射与冲突检测改键
	var rv: VBoxContainer = VBoxContainer.new()
	rv.custom_minimum_size = Vector2(510.0, 560.0)
	rv.add_theme_constant_override("separation", 8)
	cols.add_child(rv)

	rv.add_child(_ink_lbl("◆ 纯 PC 键鼠快捷栏映射（点击键位后按键重绑，自动拦截冲突）：", 19, Color("#5A3320")))
	_rebind_status_lbl = _ink_lbl("铁律：Space 专属于【战术凝时】，Enter 专属于【推进对话】，严禁混绑。", 16, Color("#23483E"))
	rv.add_child(_rebind_status_lbl)

	var rebind_rows: Array[Array] = [
		["tactical_pause", "战场【战术凝时】"],
		["skill_q", "专属打断 / 位移 (Q)"],
		["skill_e", "职责招牌技 (E)"],
		["skill_r", "本命古宝大招 (R)"],
		["skill_g", "双人羁绊合击 (G)"],
		["interact", "场景交互 / 破禁 (F)"],
		["world_map", "青岚舆图 (M)"],
		["casket_cultivation", "修行·兵甲 (C)"],
		["casket_inventory", "行囊·剑匣 (B)"],
		["casket_journal", "问道手札 (J)"],
	]
	for rpair: Array in rebind_rows:
		var act_id: String = str(rpair[0])
		var khb: HBoxContainer = HBoxContainer.new()
		rv.add_child(khb)
		var klbl: Label = _ink_lbl(str(rpair[1]), 16, UIThemeBuilder.COL_INK_DARK)
		klbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		khb.add_child(klbl)
		var kbtn: Button = Button.new()
		kbtn.focus_mode = Control.FOCUS_NONE
		kbtn.custom_minimum_size = Vector2(130.0, 34.0)
		kbtn.text = "按键中..." if _rebinding_action == act_id else InputRouter.get_key_label(act_id)
		kbtn.pressed.connect(func() -> void:
			_rebinding_action = act_id
			_rebind_status_lbl.text = "请按下新按键绑定【%s】..." % str(rpair[1])
		)
		khb.add_child(kbtn)

	var reset_kb: Button = Button.new()
	reset_kb.text = "恢复出厂黄金键位"
	reset_kb.focus_mode = Control.FOCUS_NONE
	reset_kb.pressed.connect(func() -> void:
		InputRouter.reset_default_keybinds()
		SaveManager.save_settings()
		open_settings_modal()
	)
	rv.add_child(reset_kb)


func open_chapter_complete_modal() -> void:
	_open_base("chapter_done", Vector2(920.0, 560.0))
	_add_header("【第一卷 · 山雨欲来风满楼 · 圆满收卷】")

	var choice: String = str(CampaignState.world_flags.get("marrow_choice", "scatter"))
	var seal_txt: String = "朱砂签 ·【纳髓入匣】（执道孤峰，直破炼气二层）" if choice == "absorb" else "朱砂签 ·【一念化雨】（悬壶济镇，无瑕炼气二层）"

	var summary: Label = _ink_lbl(
		"恭喜道友打通《尘缘问道》第一章青岚境精品垂直切片！\n\n"
		+ "◆ 当前修为：炼气二层（天道无瑕道基 · 寿元 120 载）\n"
		+ "◆ 本章道心烙印：%s\n" % seal_txt
		+ "◆ 同道羁绊：沈清禾（%s） · 裴照（%s）\n" % [
			tr(CampaignState.BOND_TIER_KEYS[clampi(int(CampaignState.companion_bonds.get("shen_qinghe", 1)) - 1, 0, 4)]),
			tr(CampaignState.BOND_TIER_KEYS[clampi(int(CampaignState.companion_bonds.get("pei_zhao", 1)) - 1, 0, 4)])
		]
		+ "\n您可合卷继续在青岚三连箱庭自由游历、炼丹、探索支线并留存道卷，以待第二章【青云境 · 云台冷眼试青锋】开启！",
		19, UIThemeBuilder.COL_INK_DARK
	)
	_card_vbox.add_child(summary)

	var hb: HBoxContainer = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 24)
	_card_vbox.add_child(hb)

	var cont_b: Button = Button.new()
	cont_b.text = "继续游历青岚境"
	cont_b.focus_mode = Control.FOCUS_NONE
	cont_b.pressed.connect(close_modal)
	hb.add_child(cont_b)

	var title_b: Button = Button.new()
	title_b.text = "留存自动道卷并返回标题"
	title_b.focus_mode = Control.FOCUS_NONE
	title_b.pressed.connect(func() -> void:
		SaveManager.save_rolling_auto()
		close_modal()
		return_to_title_requested.emit()
	)
	hb.add_child(title_b)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _brew_running and event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_brew_heat(0.06)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_brew_heat(-0.06)
		return

	if _rebinding_action != "" and event is InputEventKey:
		var kev: InputEventKey = event as InputEventKey
		if kev.pressed and not kev.echo:
			var code: Key = kev.physical_keycode if kev.physical_keycode != KEY_NONE else kev.keycode
			if code == KEY_ESCAPE:
				_rebinding_action = ""
				open_settings_modal()
			else:
				var res: Dictionary = InputRouter.rebind_action(_rebinding_action, int(code))
				if bool(res.get("ok", false)):
					_rebinding_action = ""
					SaveManager.save_settings()
					open_settings_modal()
				else:
					_rebind_status_lbl.text = "【键位冲突】该键已被【%s】占用，请换用其他键！" % str(res.get("conflict", ""))
					_rebind_status_lbl.add_theme_color_override("font_color", UIThemeBuilder.COL_CINNABAR_RED)
			get_viewport().set_input_as_handled()


func _add_slider_row(parent: VBoxContainer, label_txt: String, init_val: float, on_change: Callable) -> void:
	var hb: HBoxContainer = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	parent.add_child(hb)
	var l: Label = _ink_lbl("%s (%d%%)" % [label_txt, int(round(init_val * 100.0))], 16, UIThemeBuilder.COL_INK_DARK)
	l.custom_minimum_size = Vector2(260.0, 28.0)
	hb.add_child(l)
	var sl: HSlider = HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = init_val
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(func(v: float) -> void:
		l.text = "%s (%d%%)" % [label_txt, int(round(v * 100.0))]
		on_change.call(v)
	)
	hb.add_child(sl)


func _ink_lbl(txt: String, fsize: int, col: Color) -> Label:
	var l: Label = Label.new()
	l.text = txt
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", maxi(UIThemeBuilder.FS_MIN, fsize))
	l.add_theme_color_override("font_color", col)
	return l
