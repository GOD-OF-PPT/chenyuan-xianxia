class_name DaoCasketPanel
extends ColorRect
## 第三层唯一功能菜单《万象道匣》（严格对齐 docs/design/21-ui-ux-spec.md 第 3.2 节）
## 顶栏页签收束（切片开放 4 大核心页签，未解锁灵兽打书页签彻底隐藏不画灰锁）：
## - Tab 1【修行·兵甲 (C)】：角色切换 + 水墨经脉境界图 + 五维自由潜能加点/洗髓重置 + 5 槽装备 + 真实递减面板详表
## - Tab 2【道途·奇门 (N)】：双分支道途专精树（脱战一键切流派） + 奇门常驻光环阵图与 1~4 阵位调换
## - Tab 3【行囊·剑匣 (B)】：分类行囊 + 并排蓝字装备对比 + 快捷丹槽设置 + 【断玉剑匣·混元提纯】蕴灵槽与丹方录
## - Tab 5【问道手札 (J)】：四卷线索手札 + 五大势力声望 + 同伴五阶词牌羁绊 + 朱砂因果水墨签 + 前尘绘卷 CG 回看

signal replay_cg_requested(cg_id: String)
signal casket_closed()

var audio_director: AudioDirector = null
var active_tab: String = "cultivation"
var selected_char_id: String = "gu_changqing"
var selected_inv_filter: String = "all"
var selected_item_id: String = ""
var selected_journal_vol: String = "main"

var _tab_buttons: Dictionary = {}
var _content_root: MarginContainer


func _ready() -> void:
	UIThemeBuilder.bind_full_rect(self)
	color = Color(0.05, 0.04, 0.04, 0.80)
	visible = false
	theme = UIThemeBuilder.get_global_theme()

	var center: CenterContainer = CenterContainer.new()
	add_child(center)
	UIThemeBuilder.bind_full_rect(center)

	var frame: PanelContainer = PanelContainer.new()
	frame.custom_minimum_size = Vector2(1620.0, 910.0)
	frame.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.12, 0.10, 0.09, 0.98), UIThemeBuilder.COL_BRONZE_GOLD, 3, 8))
	center.add_child(frame)

	var root_v: VBoxContainer = VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 10)
	frame.add_child(root_v)

	# 顶部乌木错金页签栏
	var top_bar: HBoxContainer = HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 14)
	root_v.add_child(top_bar)

	var title_lbl: Label = Label.new()
	title_lbl.text = "  《万象道匣》  "
	title_lbl.add_theme_font_size_override("font_size", UIThemeBuilder.FS_HEADER)
	title_lbl.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD)
	top_bar.add_child(title_lbl)

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
		tbtn.custom_minimum_size = Vector2(235.0, 48.0)
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
	close_btn.pressed.connect(close_casket)
	top_bar.add_child(close_btn)

	_content_root = MarginContainer.new()
	_content_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_root.add_theme_constant_override("margin_left", 18)
	_content_root.add_theme_constant_override("margin_right", 18)
	_content_root.add_theme_constant_override("margin_top", 8)
	_content_root.add_theme_constant_override("margin_bottom", 14)
	root_v.add_child(_content_root)


func open_tab(tab_id: String) -> void:
	if visible and active_tab == tab_id:
		# 再次按相同页签热键直接合卷归位
		close_casket()
		return
	active_tab = tab_id
	if not CampaignState.recruited_order.has(selected_char_id):
		selected_char_id = "gu_changqing"
	visible = true
	InputRouter.set_mode(InputRouter.MODE_MODAL_MENU)
	if audio_director != null:
		audio_director.play_sfx("sfx_ui_page_turn", AudioDirector.TIER_B, true)
	rebuild_current_tab()


func close_casket() -> void:
	if not visible:
		return
	visible = false
	InputRouter.set_mode(InputRouter.MODE_WORLD_COMBAT)
	if audio_director != null:
		audio_director.play_sfx("sfx_ui_jade_click", AudioDirector.TIER_B, true)
	casket_closed.emit()


func rebuild_current_tab() -> void:
	if not visible:
		return
	CampaignState.recalculate_all_party_stats(false)

	for tid_var: Variant in _tab_buttons.keys():
		var tid: String = str(tid_var)
		var b: Button = _tab_buttons[tid] as Button
		b.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD if tid == active_tab else UIThemeBuilder.COL_XUAN_WARM)

	var sb_lbl: Label = find_child("StonesBadge", true, false) as Label
	if sb_lbl != null:
		sb_lbl.text = "◆ %s：%d   " % [tr("TERM_SPIRIT_STONE"), CampaignState.spirit_stones]

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


## ==================== Tab 1：【修行 · 兵甲】 ====================
func _build_tab_cultivation() -> void:
	var cols: HBoxContainer = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	_content_root.add_child(cols)

	var m: Dictionary = CampaignState.party_members.get(selected_char_id, {}) as Dictionary
	var cdef: Dictionary = DataDB.get_character(selected_char_id)
	var rdef: Dictionary = DataDB.get_realm(str(m.get("realm_id", "mortal")))
	var sheet: Dictionary = m.get("sheet", {}) as Dictionary

	# 左栏：同行角色切换 + 水墨经脉境界图
	var left_card: PanelContainer = _make_xuan_column(440.0)
	cols.add_child(left_card)
	var lv: VBoxContainer = VBoxContainer.new()
	lv.add_theme_constant_override("separation", 10)
	left_card.add_child(lv)

	var char_row: HBoxContainer = HBoxContainer.new()
	char_row.add_theme_constant_override("separation", 8)
	lv.add_child(char_row)
	for cid: String in CampaignState.recruited_order:
		var cd: Dictionary = DataDB.get_character(cid)
		var cb: Button = Button.new()
		cb.focus_mode = Control.FOCUS_NONE
		cb.text = ("★ " if cid == selected_char_id else "") + DataDB.loc(str(cd.get("name_key", cid)))
		cb.pressed.connect(func() -> void:
			selected_char_id = cid
			rebuild_current_tab()
		)
		char_row.add_child(cb)

	var cname_lbl: Label = _dark_label(
		"%s · %s" % [DataDB.loc(str(cdef.get("name_key", ""))), DataDB.loc(str(cdef.get("title_key", "")))],
		21, Color("#5A3B1E")
	)
	lv.add_child(cname_lbl)

	var realm_box: PanelContainer = PanelContainer.new()
	realm_box.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.14, 0.13, 0.12, 0.96), UIThemeBuilder.COL_BRONZE_GOLD, 2, 6))
	lv.add_child(realm_box)
	var rvb: VBoxContainer = VBoxContainer.new()
	rvb.add_theme_constant_override("separation", 6)
	realm_box.add_child(rvb)

	var r_title: Label = Label.new()
	r_title.text = "【当前境界】%s（%s）" % [DataDB.loc(str(rdef.get("name_key", ""))), DataDB.loc(str(rdef.get("sub_name_key", "")))]
	r_title.add_theme_font_size_override("font_size", 20)
	r_title.add_theme_color_override("font_color", Color("#8EE5C0"))
	rvb.add_child(r_title)

	var grade_str: String = "天道无瑕道基 (+8%全五维)" if str(m.get("dao_foundation_grade", "")) == "flawless" else "地道稳固道基"
	var life_lbl: Label = Label.new()
	life_lbl.text = "道基品评：%s\n基准寿元上限：%d 载（自由探索零损耗）" % [grade_str, int(sheet.get("lifespan_max", 80))]
	life_lbl.add_theme_font_size_override("font_size", 17)
	rvb.add_child(life_lbl)

	var r_desc: Label = Label.new()
	r_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r_desc.text = DataDB.loc(str(rdef.get("desc_key", "")))
	r_desc.add_theme_font_size_override("font_size", UIThemeBuilder.FS_MIN)
	r_desc.add_theme_color_override("font_color", Color("#C9C0B2"))
	rvb.add_child(r_desc)

	# 经脉阶梯进度示意
	var ladder_lbl: Label = _dark_label(
		"◆ 修真经脉阶梯：\n  [凡人·感气] ──▶ [炼气一层·初窥] ──▶ [炼气二层·中期]\n  （破庙结阵入炼气一层 · 苍木灵髓叩问破炼气二层）",
		16, Color("#2E4B3E")
	)
	lv.add_child(ladder_lbl)

	var bio_lbl: Label = _dark_label(DataDB.loc(str(cdef.get("bio_key", ""))), 17, UIThemeBuilder.COL_INK_DARK)
	bio_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(bio_lbl)

	# 中栏：5 槽精炼兵甲 + 梦幻五维自由潜能加点器
	var mid_card: PanelContainer = _make_xuan_column(540.0)
	cols.add_child(mid_card)
	var mv: VBoxContainer = VBoxContainer.new()
	mv.add_theme_constant_override("separation", 10)
	mid_card.add_child(mv)

	mv.add_child(_dark_label("◆ 五槽随身器物（点击行囊可更换穿戴）：", 20, Color("#5A3B1E")))
	var eq_map: Dictionary = m.get("equipped", {}) as Dictionary
	var slot_cn: Dictionary = {
		"weapon": "① 佩兵",
		"robe": "② 法衣",
		"boots": "③ 履腕",
		"pendant": "④ 灵佩",
		"treasure": "⑤ 古宝",
	}
	for s_key: String in StatLedger.EQUIP_SLOTS:
		var eq_id: String = str(eq_map.get(s_key, ""))
		var edef: Dictionary = DataDB.get_equipment(eq_id)
		var row_p: PanelContainer = PanelContainer.new()
		row_p.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.15, 0.13, 0.12, 0.95), UIThemeBuilder.COL_BRONZE_DIM, 1, 4))
		mv.add_child(row_p)
		var ehb: HBoxContainer = HBoxContainer.new()
		ehb.add_theme_constant_override("separation", 10)
		row_p.add_child(ehb)
		var elbl: Label = Label.new()
		elbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ename: String = DataDB.loc(str(edef.get("name_key", ""))) if eq_id != "" else "（空置）"
		var stunt_tag: String = " ★蓝字特技" if str(edef.get("blue_stunt_id", "")) != "" else ""
		elbl.text = "%s：%s%s" % [str(slot_cn[s_key]), ename, stunt_tag]
		elbl.add_theme_font_size_override("font_size", 17)
		elbl.add_theme_color_override("font_color", UIThemeBuilder.COL_BLUE_STUNT if stunt_tag != "" else UIThemeBuilder.COL_XUAN_WARM)
		ehb.add_child(elbl)

	mv.add_child(_dark_label("◆ 梦幻五维潜能加点（剩余自由潜能：%d 点）：" % int(m.get("free_potential", 0)), 20, Color("#5A3B1E")))
	var five_vals: Dictionary = sheet.get("five_stats", {}) as Dictionary
	var alloc_vals: Dictionary = m.get("allocated_potential", {}) as Dictionary
	var five_meta: Array[Array] = [
		["con", "根骨", "+12 气血上限 / 脱战回血"],
		["spi", "灵识", "+8 真元 / +1.5 仙术 / +0.8 治疗"],
		["str", "膂力", "+1.6 兵刃飞剑强度 / 破罡力"],
		["end", "体魄", "+2.2 护甲与五灵抗性"],
		["agi", "身法", "+1.2 暴击等级 / +0.15% 移速"],
	]
	for fmeta: Array in five_meta:
		var fkey: String = str(fmeta[0])
		var fhb: HBoxContainer = HBoxContainer.new()
		fhb.add_theme_constant_override("separation", 8)
		mv.add_child(fhb)
		var flbl: Label = _dark_label(
			"%s：%d（已投 +%d）· %s" % [str(fmeta[1]), int(five_vals.get(fkey, 6)), int(alloc_vals.get(fkey, 0)), str(fmeta[2])],
			16, UIThemeBuilder.COL_INK_DARK
		)
		flbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fhb.add_child(flbl)
		var plus_b: Button = Button.new()
		plus_b.text = "+1"
		plus_b.focus_mode = Control.FOCUS_NONE
		plus_b.disabled = int(m.get("free_potential", 0)) <= 0 or NotifyHub.combat_active
		plus_b.pressed.connect(func() -> void:
			if CampaignState.allocate_potential_point(selected_char_id, fkey, 1):
				rebuild_current_tab()
		)
		fhb.add_child(plus_b)

	var reset_btn: Button = Button.new()
	reset_btn.text = "服用【洗髓灵露】无损重置五维（存量：%d）" % CampaignState.get_item_count("item_marrow_dew")
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.disabled = CampaignState.get_item_count("item_marrow_dew") <= 0 or NotifyHub.combat_active
	reset_btn.pressed.connect(func() -> void:
		if CampaignState.reset_potential_points(selected_char_id):
			rebuild_current_tab()
	)
	mv.add_child(reset_btn)

	# 右栏：100% 真实递减换算生效详表（零隐藏暗改）
	var right_card: PanelContainer = _make_xuan_column(540.0)
	cols.add_child(right_card)
	var rv: VBoxContainer = VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right_card.add_child(rv)

	rv.add_child(_dark_label("◆ 最终生效面板（45/35/20 三桶预算与双曲递减实算）：", 20, Color("#5A3B1E")))
	var bbreak: Dictionary = sheet.get("bucket_breakdown", {}) as Dictionary
	var stat_lines: Array[String] = [
		"· 最大气血：%d / %d（境界潜能基石 %d + 兵甲套装 %d）" % [int(m.get("hp", 120)), int(sheet.get("max_hp", 120)), int(bbreak.get("bucket_a_hp", 100)), int(bbreak.get("bucket_b_hp", 0))],
		"· 最大真元：%d / %d" % [int(m.get("mp", 60)), int(sheet.get("max_mp", 60))],
		"· 兵刃/飞剑强度：%.1f   |   仙术强度：%.1f" % [float(sheet.get("phys_power", 14.0)), float(sheet.get("spell_power", 14.0))],
		"· 医道治疗强度：%.1f" % float(sheet.get("heal_power", 12.0)),
		"· 暴击率：%.1f%%（等级 %.0f，暴伤 %.0f%%）" % [float(sheet.get("crit_pct", 0.05)) * 100.0, float(sheet.get("crit_rating", 0.0)), float(sheet.get("crit_mult", 1.6)) * 100.0],
		"· 施法与普攻急速：%.1f%%（当前全局调息 GCD = %.2fs，普攻间隔 %.2fs）" % [float(sheet.get("haste_pct", 0.0)) * 100.0, float(sheet.get("gcd_sec", 1.5)), float(sheet.get("attack_interval", 1.75))],
		"· 破罡精通：%.1f%%（克制削罡倍率 ×%.2f，相生连携伤害 ×%.2f）" % [float(sheet.get("mastery_pct", 0.0)) * 100.0, float(sheet.get("ward_break_mult", 1.0)) * 2.5, float(sheet.get("synergy_dmg_mult", 1.0))],
		"· 护甲御守对同境综合减伤：%.1f%%（御守 %.1f%%）" % [float(sheet.get("mitigation_pct", 0.15)) * 100.0, float(sheet.get("vers_pct", 0.0)) * 100.0],
		"· 战场移动速度：%.0f   |   杀意（仇恨）系数：×%.2f" % [float(sheet.get("move_speed_px", 215.0)), float(sheet.get("threat_mult", 1.0))],
		"· 经脉暗伤层数：%d 层（引灵石碑休整或服回春散清除）" % int(m.get("meridian_bruise", 0)),
	]
	for sl: String in stat_lines:
		rv.add_child(_dark_label(sl, 17, UIThemeBuilder.COL_INK_DARK))

	var set_counts: Dictionary = sheet.get("set_counts", {}) as Dictionary
	if not set_counts.is_empty():
		rv.add_child(_dark_label("◆ 已激活宗门套装共鸣：", 19, Color("#23483E")))
		for sid_var: Variant in set_counts.keys():
			var sid: String = str(sid_var)
			var cnt: int = int(set_counts[sid])
			var sdef: Dictionary = DataDB.equip_sets.get(sid, {}) as Dictionary
			rv.add_child(_dark_label(
				"  【%s】(%d/3件)\n   · %s\n   · %s" % [
					DataDB.loc(str(sdef.get("name_key", sid))), cnt,
					DataDB.loc(str(sdef.get("desc_2pc_key", ""))),
					DataDB.loc(str(sdef.get("desc_3pc_key", "")))
				], 16, Color("#2B4C3F")
			))


## ==================== Tab 2：【道途 · 奇门】 ====================
func _build_tab_specialization() -> void:
	var cols: HBoxContainer = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	_content_root.add_child(cols)

	# 左半：双分支道途专精树（脱战随时零成本一键切换）
	var left_card: PanelContainer = _make_xuan_column(860.0)
	cols.add_child(left_card)
	var lv: VBoxContainer = VBoxContainer.new()
	lv.add_theme_constant_override("separation", 10)
	left_card.add_child(lv)

	var char_row: HBoxContainer = HBoxContainer.new()
	char_row.add_theme_constant_override("separation", 8)
	lv.add_child(char_row)
	for cid: String in CampaignState.recruited_order:
		var cd: Dictionary = DataDB.get_character(cid)
		var cb: Button = Button.new()
		cb.focus_mode = Control.FOCUS_NONE
		cb.text = ("★ " if cid == selected_char_id else "") + DataDB.loc(str(cd.get("name_key", cid)))
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
		scard.custom_minimum_size = Vector2(398.0, 680.0)
		scard.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(
			Color(0.14, 0.13, 0.11, 0.96),
			UIThemeBuilder.COL_BRONZE_GOLD if is_cur else UIThemeBuilder.COL_BRONZE_DIM,
			3 if is_cur else 1, 6
		))
		spec_hb.add_child(scard)

		var sv: VBoxContainer = VBoxContainer.new()
		sv.add_theme_constant_override("separation", 10)
		scard.add_child(sv)

		var stitle: Label = Label.new()
		stitle.text = "%s【%s】" % ["★ 当前生效 · " if is_cur else "", DataDB.loc(str(sp_def.get("name_key", skey)))]
		stitle.add_theme_font_size_override("font_size", 21)
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

		sv.add_child(Label.new())
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
					DataDB.loc(str(nd.get("desc_key", "")))
				]
				nlbl.add_theme_font_size_override("font_size", 16)
				nlbl.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD if lit else Color("#A59D92"))
				sv.add_child(nlbl)

	# 右半：梦幻式奇门常驻光环阵法与 1~4 号阵位编排
	var right_card: PanelContainer = _make_xuan_column(680.0)
	cols.add_child(right_card)
	var rv: VBoxContainer = VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	right_card.add_child(rv)

	rv.add_child(_dark_label("◆ 奇门常驻光环阵法（不绑地面范围，走位完全自由）：", 20, Color("#5A3B1E")))
	for fid: String in ["scatter", "tianfu", "dizai"]:
		var fdef: Dictionary = DataDB.get_formation(fid)
		var is_unlocked: bool = CampaignState.unlocked_formations.has(fid)
		var is_active: bool = (CampaignState.active_formation_id == fid)
		var fbox: PanelContainer = PanelContainer.new()
		fbox.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(
			Color(0.15, 0.13, 0.12, 0.95),
			UIThemeBuilder.COL_BRONZE_GOLD if is_active else UIThemeBuilder.COL_BRONZE_DIM,
			2 if is_active else 1, 5
		))
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
		fbtn.disabled = (not is_unlocked) or is_active
		fbtn.pressed.connect(func() -> void:
			CampaignState.set_active_formation(fid)
			rebuild_current_tab()
		)
		ftop.add_child(fbtn)

		var fdesc: Label = Label.new()
		fdesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fdesc.text = DataDB.loc(str(fdef.get("desc_key", "")))
		fdesc.add_theme_font_size_override("font_size", 16)
		fvb.add_child(fdesc)

	rv.add_child(_dark_label("◆ 四象阵位职责分配（点击【与下位互换】自由调整谁站玄武主坦位）：", 19, Color("#5A3B1E")))
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
				float(smod.get("damage_mult", 1.0)), float(smod.get("damage_taken_mult", 1.0)), float(smod.get("threat_mult", 1.0))
			], 16, UIThemeBuilder.COL_INK_DARK
		)
		slbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shb.add_child(slbl)

		if slot_n < 4:
			var swap_b: Button = Button.new()
			swap_b.text = "↕ 互换 %d/%d" % [slot_n, slot_n + 1]
			swap_b.focus_mode = Control.FOCUS_NONE
			swap_b.disabled = NotifyHub.combat_active
			swap_b.pressed.connect(func() -> void:
				CampaignState.swap_formation_slots(slot_n, slot_n + 1)
				rebuild_current_tab()
			)
			shb.add_child(swap_b)


## ==================== Tab 3：【行囊 · 剑匣】 ====================
func _build_tab_inventory_and_sword_box() -> void:
	var cols: HBoxContainer = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	_content_root.add_child(cols)

	# 左栏：分类行囊与一键整理 + 装备并排对比/使用面板
	var left_card: PanelContainer = _make_xuan_column(920.0)
	cols.add_child(left_card)
	var lv: VBoxContainer = VBoxContainer.new()
	lv.add_theme_constant_override("separation", 10)
	left_card.add_child(lv)

	var filter_hb: HBoxContainer = HBoxContainer.new()
	filter_hb.add_theme_constant_override("separation", 8)
	lv.add_child(filter_hb)
	for fpair: Array in [["all", "全部"], ["equip", "兵甲灵佩"], ["pill", "丹药灵符"], ["mat", "灵材奇物"]]:
		var fk: String = str(fpair[0])
		var fb: Button = Button.new()
		fb.focus_mode = Control.FOCUS_NONE
		fb.text = ("★ " if selected_inv_filter == fk else "") + str(fpair[1])
		fb.pressed.connect(func() -> void:
			selected_inv_filter = fk
			rebuild_current_tab()
		)
		filter_hb.add_child(fb)

	var sort_b: Button = Button.new()
	sort_b.text = "按品阶整理"
	sort_b.focus_mode = Control.FOCUS_NONE
	sort_b.pressed.connect(func() -> void:
		CampaignState.sort_inventory_by_grade()
		rebuild_current_tab()
	)
	filter_hb.add_child(sort_b)

	var split_hb: HBoxContainer = HBoxContainer.new()
	split_hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_hb.add_theme_constant_override("separation", 14)
	lv.add_child(split_hb)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(430.0, 660.0)
	split_hb.add_child(scroll)

	var list_v: VBoxContainer = VBoxContainer.new()
	list_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_v.add_theme_constant_override("separation", 6)
	scroll.add_child(list_v)

	for entry: Dictionary in CampaignState.inventory:
		var iid: String = str(entry.get("id", ""))
		var cnt: int = int(entry.get("count", 0))
		var is_eq: bool = DataDB.equipment.has(iid)
		var idef: Dictionary = DataDB.get_any_item_or_equip(iid)
		var cat: String = str(idef.get("category", "equip" if is_eq else "material"))
		if selected_inv_filter == "equip" and not is_eq:
			continue
		if selected_inv_filter == "pill" and not ["instant_pill", "elixir", "talisman", "breakthrough"].has(cat):
			continue
		if selected_inv_filter == "mat" and (is_eq or ["instant_pill", "elixir", "talisman"].has(cat)):
			continue

		if selected_item_id == "":
			selected_item_id = iid

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

	# 详情与并排对比窗
	var detail_box: PanelContainer = PanelContainer.new()
	detail_box.custom_minimum_size = Vector2(440.0, 660.0)
	detail_box.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.14, 0.12, 0.11, 0.96), UIThemeBuilder.COL_BRONZE_DIM, 2, 6))
	split_hb.add_child(detail_box)

	var dv: VBoxContainer = VBoxContainer.new()
	dv.add_theme_constant_override("separation", 10)
	detail_box.add_child(dv)

	if selected_item_id != "" and CampaignState.get_item_count(selected_item_id) > 0:
		var sel_def: Dictionary = DataDB.get_any_item_or_equip(selected_item_id)
		var is_sel_eq: bool = DataDB.equipment.has(selected_item_id)
		var dtitle: Label = Label.new()
		dtitle.text = "【%s】" % DataDB.loc(str(sel_def.get("name_key", selected_item_id)))
		dtitle.add_theme_font_size_override("font_size", 22)
		dtitle.add_theme_color_override("font_color", UIThemeBuilder.COL_BLUE_STUNT if str(sel_def.get("blue_stunt_id", "")) != "" else UIThemeBuilder.COL_BRONZE_GOLD)
		dv.add_child(dtitle)

		var ddesc: Label = Label.new()
		ddesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ddesc.text = DataDB.loc(str(sel_def.get("desc_key", "")))
		ddesc.add_theme_font_size_override("font_size", 17)
		dv.add_child(ddesc)

		if is_sel_eq:
			var slot_s: String = str(sel_def.get("slot", "weapon"))
			dv.add_child(Label.new())
			var cmp_lbl: Label = Label.new()
			cmp_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cmp_lbl.text = _format_equip_comparison(selected_char_id, sel_def, slot_s)
			cmp_lbl.add_theme_font_size_override("font_size", 16)
			cmp_lbl.add_theme_color_override("font_color", Color("#9EE0C4"))
			dv.add_child(cmp_lbl)

			for target_cid: String in CampaignState.recruited_order:
				var tname: String = DataDB.loc(str(DataDB.get_character(target_cid).get("name_key", target_cid)))
				var eq_b: Button = Button.new()
				eq_b.text = "由【%s】穿戴此器物" % tname
				eq_b.focus_mode = Control.FOCUS_NONE
				eq_b.disabled = NotifyHub.combat_active
				eq_b.pressed.connect(func() -> void:
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
				use_b.pressed.connect(func() -> void:
					CampaignState.use_out_of_combat_item(selected_item_id)
					rebuild_current_tab()
				)
				dv.add_child(use_b)

			if icat == "instant_pill" or icat == "talisman":
				for qslot: String in ["5", "6"]:
					var bind_b: Button = Button.new()
					bind_b.text = "装入快捷丹符槽 [%s]" % qslot
					bind_b.focus_mode = Control.FOCUS_NONE
					bind_b.pressed.connect(func() -> void:
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
				pur_b.disabled = not CampaignState.sword_box_slot.is_empty()
				pur_b.pressed.connect(func() -> void:
					if CampaignState.start_sword_box_purify(selected_item_id):
						if audio_director != null:
							audio_director.play_sfx("sfx_sword_box_hum", AudioDirector.TIER_A, true)
						rebuild_current_tab()
				)
				dv.add_child(pur_b)

	# 右栏：【断玉剑匣 · 混元提纯】专属洞天暗格与丹方录
	var right_card: PanelContainer = _make_xuan_column(620.0)
	cols.add_child(right_card)
	var rv: VBoxContainer = VBoxContainer.new()
	rv.add_theme_constant_override("separation", 12)
	right_card.add_child(rv)

	rv.add_child(_dark_label("◆ 绝密古宝【断玉剑匣 · 混元提纯暗格】：", 21, Color("#23483E")))
	rv.add_child(_dark_label("将焦黑废丹、凡品凝气草、腐骨幽花或地摊蒙尘残铁片放入匣中，每历 3 场斗法（或引灵石碑休整）即可汲取游离混沌气淬炼为无瑕极品！", 16, UIThemeBuilder.COL_INK_DARK))

	var box_panel: PanelContainer = PanelContainer.new()
	box_panel.custom_minimum_size = Vector2(560.0, 175.0)
	box_panel.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.10, 0.16, 0.14, 0.97), UIThemeBuilder.COL_JADE_GREEN, 2, 6))
	rv.add_child(box_panel)

	var bvb: VBoxContainer = VBoxContainer.new()
	bvb.alignment = BoxContainer.ALIGNMENT_CENTER
	bvb.add_theme_constant_override("separation", 10)
	box_panel.add_child(bvb)

	if CampaignState.sword_box_slot.is_empty():
		var empty_l: Label = Label.new()
		empty_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_l.text = "【一号蕴灵暗格：空置待纳】\n（可在左侧行囊选中【焦黑废丹】或灵材点击置入）"
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
			("已淬炼圆满！可立即开匣取宝" if rem_b <= 0 else ("尚需经历 %d 场真实战斗（或石碑休整）" % rem_b))
		]
		slot_l.add_theme_font_size_override("font_size", 18)
		slot_l.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD if rem_b <= 0 else Color("#B8E6D4"))
		bvb.add_child(slot_l)

		var claim_b: Button = Button.new()
		claim_b.text = "开匣收取提纯至宝"
		claim_b.focus_mode = Control.FOCUS_NONE
		claim_b.disabled = rem_b > 0
		claim_b.pressed.connect(func() -> void:
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
					CampaignState.get_item_count(mid)
				])
		rv.add_child(_dark_label(
			"· 【%s】%s\n   配伍：%s" % [
				DataDB.loc(str(rdef.get("name_key", rid))),
				" ★已解锁一键完美速炼" if is_qb else "（待首炼15s文武控火）",
				" + ".join(ing_parts)
			], 16, Color("#23483E") if is_qb else UIThemeBuilder.COL_INK_DARK
		))


func _format_equip_comparison(char_id: String, new_def: Dictionary, slot_s: String) -> String:
	var m: Dictionary = CampaignState.party_members.get(char_id, {}) as Dictionary
	var eq_map: Dictionary = m.get("equipped", {}) as Dictionary
	var cur_id: String = str(eq_map.get(slot_s, ""))
	var cur_def: Dictionary = DataDB.get_equipment(cur_id)
	var cur_name: String = DataDB.loc(str(cur_def.get("name_key", ""))) if cur_id != "" else "无"
	var lines: PackedStringArray = PackedStringArray(["【与 %s 当前穿戴（%s）对比】：" % [DataDB.loc(str(DataDB.get_character(char_id).get("name_key", char_id))), cur_name]])
	var n_st: Dictionary = new_def.get("stats", {}) as Dictionary
	var c_st: Dictionary = cur_def.get("stats", {}) as Dictionary
	var labels: Dictionary = {
		"hp": "气血", "mp": "真元", "phys_power": "兵刃强度", "spell_power": "仙术强度",
		"heal_power": "治疗强度", "defense": "护甲抗性", "crit_rating": "暴击等级",
		"haste_rating": "急速等级", "mastery_rating": "破罡精通", "vers_rating": "御守等级"
	}
	for k_var: Variant in labels.keys():
		var k: String = str(k_var)
		var nv: float = float(n_st.get(k, 0.0))
		var cv: float = float(c_st.get(k, 0.0))
		if nv != 0.0 or cv != 0.0:
			var diff: float = nv - cv
			lines.append("  · %s：%.0f (%s%.0f)" % [str(labels[k]), nv, "+" if diff >= 0.0 else "", diff])
	var stunt_id: String = str(new_def.get("blue_stunt_id", ""))
	if stunt_id != "":
		var st_def: Dictionary = DataDB.get_skill(stunt_id)
		lines.append("  ★ 蓝字特技：【%s】" % DataDB.loc(str(st_def.get("name_key", stunt_id))))
	return "\n".join(lines)


## ==================== Tab 5：【问道手札】 ====================
func _build_tab_journal() -> void:
	var cols: HBoxContainer = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	_content_root.add_child(cols)

	# 左半：线装四卷《问道手札》（无叹号、无自动寻路，纯正第一人称线索笔录）
	var left_card: PanelContainer = _make_xuan_column(860.0)
	cols.add_child(left_card)
	var lv: VBoxContainer = VBoxContainer.new()
	lv.add_theme_constant_override("separation", 10)
	left_card.add_child(lv)

	var vol_hb: HBoxContainer = HBoxContainer.new()
	vol_hb.add_theme_constant_override("separation", 8)
	lv.add_child(vol_hb)
	for vpair: Array in [["main", "求仙主脉"], ["side", "红尘奇遇"], ["relic", "残碑秘辛"], ["lore", "博物风土"]]:
		var vk: String = str(vpair[0])
		var vb: Button = Button.new()
		vb.focus_mode = Control.FOCUS_NONE
		vb.text = ("★ " if selected_journal_vol == vk else "") + str(vpair[1])
		vb.pressed.connect(func() -> void:
			selected_journal_vol = vk
			rebuild_current_tab()
		)
		vol_hb.add_child(vb)

	var jscroll: ScrollContainer = ScrollContainer.new()
	jscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(jscroll)

	var jlist: VBoxContainer = VBoxContainer.new()
	jlist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jlist.add_theme_constant_override("separation", 12)
	jscroll.add_child(jlist)

	# 当前进行中的主支线阶段摘要
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
		jlist.add_child(_dark_label(
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
		entry_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		jlist.add_child(entry_lbl)

	# 右半：同道五阶词牌羁绊 + 五大势力声望 + 因果水墨签 + 前尘绘卷 CG 鉴赏
	var right_card: PanelContainer = _make_xuan_column(680.0)
	cols.add_child(right_card)
	var rv: VBoxContainer = VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	right_card.add_child(rv)

	rv.add_child(_dark_label("◆ 同道五阶羁绊词牌（二阶解锁 G 键双人羁绊合击）：", 20, Color("#5A3B1E")))
	for comp_id: String in ["shen_qinghe", "pei_zhao"]:
		var btier: int = clampi(int(CampaignState.companion_bonds.get(comp_id, 1)), 1, 5)
		var cname: String = DataDB.loc(str(DataDB.get_character(comp_id).get("name_key", comp_id)))
		var ult_note: String = "（已开启合击【青莲引剑】）" if comp_id == "shen_qinghe" and btier >= 2 else ""
		rv.add_child(_dark_label("  · %s：%s %s" % [cname, tr(CampaignState.BOND_TIER_KEYS[btier - 1]), ult_note], 18, Color("#23483E")))

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
		rv.add_child(_dark_label("  （尚未落印重大章节因果签）", 16, Color("#6E655C")))
	else:
		for seal_id: String in CampaignState.ink_seals:
			var sdef: Dictionary = DataDB.ink_seals.get(seal_id, {}) as Dictionary
			rv.add_child(_dark_label(
				"  印鉴：%s\n  “%s”" % [DataDB.loc(str(sdef.get("name_key", seal_id))), DataDB.loc(str(sdef.get("poem_key", "")))],
				17, Color("#8E2822")
			))

	rv.add_child(_dark_label("◆ 前尘绘卷（全屏动态 CG 回看）：", 19, Color("#5A3B1E")))
	var cg_btn: Button = Button.new()
	var has_cg1: bool = CampaignState.unlocked_cgs.has("cg_ch01_ruined_temple")
	cg_btn.text = "重温绘卷一：《破庙剑鸣会少年》" if has_cg1 else "绘卷一：破庙初会解锁后可随时鉴赏"
	cg_btn.focus_mode = Control.FOCUS_NONE
	cg_btn.disabled = not has_cg1
	cg_btn.pressed.connect(func() -> void:
		close_casket()
		replay_cg_requested.emit("cg_ch01_ruined_temple")
	)
	rv.add_child(cg_btn)


func _make_xuan_column(min_w: float) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.custom_minimum_size = Vector2(min_w, 780.0)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", UIThemeBuilder.make_xuan_paper_box(Color("#7A5F3E"), 2))
	return p


func _dark_label(txt: String, fsize: int, col: Color) -> Label:
	var l: Label = Label.new()
	l.text = txt
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", maxi(UIThemeBuilder.FS_MIN, fsize))
	l.add_theme_color_override("font_color", col)
	return l
