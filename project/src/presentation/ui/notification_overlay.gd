class_name NotificationOverlay
extends Control
## 第三层唯一通知渲染出口（对接 NotifyHub 四级优先级信号）
## 严禁其他模块私自向屏幕弹浮窗或乱画飘字！
## - P0 系统级危机（损坏存档零覆盖保护弹窗，支持一键恢复 .bak 备份）
## - P1 战斗核心横幅与 AoE 归并伤害跳字（字号 >=16px）
## - P3 右侧旧宣纸收获轻签（最多同时 2 条优雅滑入淡出）

signal backup_recovery_chosen(slot_id: String)

var world_camera: Camera2D = null

var _banner_box: PanelContainer
var _banner_label: Label
var _banner_timer: float = 0.0

var _slip_vbox: VBoxContainer
var _floater_layer: Control
var _floaters: Array[Dictionary] = []

var _crisis_modal: ColorRect
var _crisis_title: Label
var _crisis_body: Label
var _crisis_bak_btn: Button
var _pending_crisis_slot: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UIThemeBuilder.get_global_theme()

	_floater_layer = Control.new()
	_floater_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floater_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_floater_layer)

	# 顶部偏上战斗核心横幅（P1）
	_banner_box = PanelContainer.new()
	_banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_box.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.12, 0.10, 0.09, 0.90), UIThemeBuilder.COL_BRONZE_GOLD, 2, 6))
	_banner_box.anchor_left = 0.5
	_banner_box.anchor_right = 0.5
	_banner_box.offset_left = -310.0
	_banner_box.offset_right = 310.0
	_banner_box.offset_top = 178.0
	_banner_box.offset_bottom = 224.0
	_banner_box.visible = false
	add_child(_banner_box)

	_banner_label = Label.new()
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_size_override("font_size", UIThemeBuilder.FS_SUBTITLE)
	_banner_label.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD)
	_banner_box.add_child(_banner_label)

	# 右侧偏下宣纸收获轻签容器（P3，最多同屏 2 条）
	_slip_vbox = VBoxContainer.new()
	_slip_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slip_vbox.anchor_left = 1.0
	_slip_vbox.anchor_right = 1.0
	_slip_vbox.anchor_top = 1.0
	_slip_vbox.anchor_bottom = 1.0
	_slip_vbox.offset_left = -395.0
	_slip_vbox.offset_right = -24.0
	_slip_vbox.offset_top = -310.0
	_slip_vbox.offset_bottom = -175.0
	_slip_vbox.add_theme_constant_override("separation", 10)
	add_child(_slip_vbox)

	_build_crisis_modal()

	NotifyHub.combat_banner_pushed.connect(_on_combat_banner)
	NotifyHub.combat_floater_pushed.connect(_on_combat_floater)
	NotifyHub.clear_combat_floaters_requested.connect(_on_clear_combat_floaters)
	NotifyHub.explore_slip_spawned.connect(_on_explore_slip)
	NotifyHub.crisis_alert_requested.connect(_on_crisis_alert)


func _build_crisis_modal() -> void:
	_crisis_modal = ColorRect.new()
	_crisis_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crisis_modal.color = Color(0.04, 0.04, 0.04, 0.78)
	_crisis_modal.visible = false
	add_child(_crisis_modal)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crisis_modal.add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(680.0, 290.0)
	card.add_theme_stylebox_override("panel", UIThemeBuilder.make_ebony_box(Color(0.14, 0.11, 0.10, 0.98), UIThemeBuilder.COL_CINNABAR_RED, 3, 8))
	center.add_child(card)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	card.add_child(vbox)

	_crisis_title = Label.new()
	_crisis_title.add_theme_font_size_override("font_size", UIThemeBuilder.FS_HEADER)
	_crisis_title.add_theme_color_override("font_color", UIThemeBuilder.COL_CINNABAR_RED)
	_crisis_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_crisis_title)

	_crisis_body = Label.new()
	_crisis_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_crisis_body.add_theme_font_size_override("font_size", UIThemeBuilder.FS_BODY)
	vbox.add_child(_crisis_body)

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 18)
	vbox.add_child(btn_row)

	_crisis_bak_btn = Button.new()
	_crisis_bak_btn.text = "加载自动备份 (.bak)"
	_crisis_bak_btn.focus_mode = Control.FOCUS_NONE
	_crisis_bak_btn.pressed.connect(func() -> void:
		_crisis_modal.visible = false
		if _pending_crisis_slot != "":
			backup_recovery_chosen.emit(_pending_crisis_slot)
	)
	btn_row.add_child(_crisis_bak_btn)

	var open_dir_btn: Button = Button.new()
	open_dir_btn.text = "保留损坏原文件并关闭"
	open_dir_btn.focus_mode = Control.FOCUS_NONE
	open_dir_btn.pressed.connect(func() -> void:
		_crisis_modal.visible = false
	)
	btn_row.add_child(open_dir_btn)


func _process(delta: float) -> void:
	if _banner_timer > 0.0:
		_banner_timer = maxf(0.0, _banner_timer - delta)
		_banner_box.modulate.a = clampf(_banner_timer / 0.35, 0.0, 1.0)
		if _banner_timer <= 0.0:
			_banner_box.visible = false

	for i: int in range(_floaters.size() - 1, -1, -1):
		var fl: Dictionary = _floaters[i]
		var rem: float = float(fl.get("timer", 0.0)) - delta
		var lbl: Label = fl.get("label", null) as Label
		if rem <= 0.0 or lbl == null or not is_instance_valid(lbl):
			if lbl != null and is_instance_valid(lbl):
				lbl.queue_free()
			_floaters.remove_at(i)
			continue
		fl["timer"] = rem
		var rise: float = (0.95 - rem) * 42.0
		var wpos: Vector2 = fl.get("world_pos", Vector2.ZERO) as Vector2
		var spos: Vector2 = _world_to_screen(wpos) + Vector2(-36.0, -rise)
		lbl.position = spos
		lbl.modulate.a = clampf(rem / 0.28, 0.0, 1.0)


func _on_combat_banner(payload: Dictionary) -> void:
	_banner_label.text = str(payload.get("text", ""))
	var cat: String = str(payload.get("category", "synergy"))
	if cat == "warn":
		_banner_label.add_theme_color_override("font_color", Color("#F09A7E"))
	elif cat == "ultimate" or cat == "synergy":
		_banner_label.add_theme_color_override("font_color", Color("#8EE5C0"))
	else:
		_banner_label.add_theme_color_override("font_color", UIThemeBuilder.COL_BRONZE_GOLD)
	_banner_box.visible = true
	_banner_box.modulate.a = 1.0
	_banner_timer = 2.4


func _on_combat_floater(payload: Dictionary) -> void:
	var lbl: Label = Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var amt: int = int(payload.get("amount", 0))
	var hits: int = int(payload.get("hit_count", 1))
	var is_heal: bool = bool(payload.get("is_heal", false))
	var is_crit: bool = bool(payload.get("is_crit", false))
	var elem: String = str(payload.get("element", "none"))

	var txt: String = ("+%d" % amt) if is_heal else ("-%d" % amt)
	if is_crit:
		txt = "暴击 " + txt
	if hits > 1:
		txt += " (×%d合)" % hits

	lbl.text = txt
	lbl.add_theme_font_size_override("font_size", 21 if is_crit else 17)
	var col: Color = Color("#7CE0A3") if is_heal else (Color("#FCE088") if is_crit else UIThemeBuilder.get_element_color(elem))
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", Color(0.08, 0.07, 0.06, 0.95))
	lbl.add_theme_constant_override("outline_size", 4)

	var wpos: Vector2 = payload.get("world_pos", Vector2.ZERO) as Vector2
	lbl.position = _world_to_screen(wpos)
	_floater_layer.add_child(lbl)
	_floaters.append({
		"label": lbl,
		"world_pos": wpos,
		"timer": 0.95,
	})


func _on_clear_combat_floaters() -> void:
	_banner_box.visible = false
	_banner_timer = 0.0
	for fl: Dictionary in _floaters:
		var lbl: Label = fl.get("label", null) as Label
		if lbl != null and is_instance_valid(lbl):
			lbl.queue_free()
	_floaters.clear()


func _on_explore_slip(payload: Dictionary) -> void:
	var slip: PanelContainer = PanelContainer.new()
	slip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slip.add_theme_stylebox_override("panel", UIThemeBuilder.make_xuan_paper_box(Color("#7D6339"), 2))

	var hb: VBoxContainer = VBoxContainer.new()
	hb.add_theme_constant_override("separation", 2)
	slip.add_child(hb)

	var t_lbl: Label = Label.new()
	t_lbl.text = "◆ " + str(payload.get("title", ""))
	t_lbl.add_theme_font_size_override("font_size", UIThemeBuilder.FS_MIN)
	t_lbl.add_theme_color_override("font_color", Color("#6E4826"))
	hb.add_child(t_lbl)

	var detail: String = str(payload.get("detail", ""))
	if detail != "":
		var d_lbl: Label = Label.new()
		d_lbl.text = detail
		d_lbl.add_theme_font_size_override("font_size", UIThemeBuilder.FS_BODY)
		d_lbl.add_theme_color_override("font_color", UIThemeBuilder.COL_INK_DARK)
		hb.add_child(d_lbl)

	_slip_vbox.add_child(slip)
	var tw: Tween = create_tween()
	slip.modulate.a = 0.0
	tw.tween_property(slip, "modulate:a", 1.0, 0.25)
	tw.tween_interval(2.55)
	tw.tween_property(slip, "modulate:a", 0.0, 0.35)
	tw.tween_callback(slip.queue_free)


func _on_crisis_alert(payload: Dictionary) -> void:
	_pending_crisis_slot = str(payload.get("slot_id", ""))
	_crisis_title.text = str(payload.get("title", ""))
	_crisis_body.text = str(payload.get("body", ""))
	_crisis_bak_btn.visible = bool(payload.get("has_backup", false))
	_crisis_modal.visible = true


func _world_to_screen(world_pos: Vector2) -> Vector2:
	if world_camera == null:
		return world_pos
	var vp_size: Vector2 = get_viewport_rect().size
	return (world_pos - world_camera.get_screen_center_position()) * world_camera.zoom + vp_size * 0.5
