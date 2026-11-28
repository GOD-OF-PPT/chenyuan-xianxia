class_name QinglanWorld
extends Node2D
## 第三层青岚境三连无缝箱庭主世界控制器（听雨镇&药庐 <-> 风雨山道&破庙 <-> 苍木灵枢古窟）
## 严格对齐 docs/design/12-exploration-and-levels.md 与 20-art-bible.md 第 5 节：
## - Layer 0 远景视差山水 / Layer 1 无缝矿物地表与道路 / Layer 2 Y-Sort 独立建筑树木遮挡 55% 半透 / Layer 3 斜风雨丝氛围
## - 完整串联：左键点选框选、右键自动平砍/走位/交互、Space 战术凝时、F 键破除火木水五行禁制与回环石门、三层叙事演出与动态民乐。

const ZONE_BOUNDS: Rect2 = Rect2(0.0, 0.0, 2400.0, 1400.0)

var _audio: AudioDirector
var _camera: Camera2D
var _parallax_bg: Sprite2D
var _ground_layer: Node2D
var _ground_base_sub: Node2D
var _road_feather_sub: Node2D
var _road_stone_sub: Node2D
var _road_curb_sub: Node2D
var _ground_decor_layer: Node2D
var _ysort_root: Node2D
var _ground_vfx: CombatVfxOverlay
var _sky_vfx: CombatVfxOverlay
var _rain_overlay: Node2D
var _mood_modulate: CanvasModulate
var _combat_ctrl: RtwpCombatController

## UI 层（挂载在 CanvasLayer 10）
var _ui_canvas: CanvasLayer
var _hud: CombatHud
var _casket: DaoCasketPanel
var _modals: WorldModals
var _narrative: NarrativeStage
var _recap_scroll: DefeatRecapScroll
var _notify_overlay: NotificationOverlay

## 场景内可遮挡建筑树木、可交互器物、过图传送带与小地图轮廓缓存
var _occluder_sprites: Array[Dictionary] = [] # [{sprite: Sprite2D, rect: Rect2}]
var _interactables: Array[Dictionary] = []    # [{id, kind, pos, radius, title, sprite, obstacle_idx}]
var _zone_portals: Array[Dictionary] = []     # [{rect: Rect2, target_zone: String, target_spawn: String, label: String}]
var _portal_markers: Array[Node2D] = []
var _npc_actors: Array[BattleActor] = []
var _mm_roads: Array[PackedVector2Array] = []
var _mm_buildings: Array[Rect2] = []
var _mm_steles: Array[Vector2] = []
var _mm_portals: Array[Vector2] = []

## 鼠标左键拖拽框选状态
var _lmb_down: bool = false
var _lmb_start_screen: Vector2 = Vector2.ZERO
var _is_dragging_box: bool = false

## 环境气泡与鼠标指针缓存
var _bark_cooldown: float = 4.0
var _rain_streaks: Array[Vector2] = []
var _cursor_normal: Texture2D = null
var _cursor_attack: Texture2D = null
var _cursor_interact: Texture2D = null
var _current_cursor_mode: int = -1
var _hover_outline_shader: Shader = null
var _wet_bluestone_shader: Shader = null
var _light_radial_tex: Texture2D = null
var _fg_bamboo_tex: Texture2D = null
var _fg_cave_stalactite_tex: Texture2D = null
var _alt_nameplate_overlay: Node2D = null
var _xuan_nameplate_tex: Texture2D = null
var _hovered_interactable_id: String = ""
var _alt_key_down: bool = false
var _tex_hit_images: Dictionary = {}
var _fg_bamboo_leaves: Array[Dictionary] = []
var _zone_point_lights: Array[Dictionary] = []
var _wet_road_materials: Array[ShaderMaterial] = []
var _light_flicker_clock: float = 0.0


func _ready() -> void:
	if ResourceLoader.exists("res://src/presentation/shaders/hover_outline.gdshader"):
		_hover_outline_shader = load("res://src/presentation/shaders/hover_outline.gdshader") as Shader
	if ResourceLoader.exists("res://src/presentation/shaders/wet_bluestone.gdshader"):
		_wet_bluestone_shader = load("res://src/presentation/shaders/wet_bluestone.gdshader") as Shader
	if ResourceLoader.exists("res://assets/world/light_radial_soft.png"):
		_light_radial_tex = load("res://assets/world/light_radial_soft.png") as Texture2D
	if ResourceLoader.exists("res://assets/world/fg_bamboo_leaf.png"):
		_fg_bamboo_tex = load("res://assets/world/fg_bamboo_leaf.png") as Texture2D
	if ResourceLoader.exists("res://assets/world/fg_cave_stalactite.png"):
		_fg_cave_stalactite_tex = load("res://assets/world/fg_cave_stalactite.png") as Texture2D
	if ResourceLoader.exists("res://assets/ui/frames/casket_xuan_nameplate.png"):
		_xuan_nameplate_tex = load("res://assets/ui/frames/casket_xuan_nameplate.png") as Texture2D
	_load_custom_cursors()
	_build_scene_layers()
	_build_ui_layers()
	_connect_global_signals()
	load_zone(CampaignState.current_zone_id, CampaignState.current_spawn_tag, true)


func _load_custom_cursors() -> void:
	if ResourceLoader.exists("res://assets/ui/cursors/cursor_jade_pin.png"):
		_cursor_normal = load("res://assets/ui/cursors/cursor_jade_pin.png") as Texture2D
	if ResourceLoader.exists("res://assets/ui/cursors/cursor_bronze_sword.png"):
		_cursor_attack = load("res://assets/ui/cursors/cursor_bronze_sword.png") as Texture2D
	if ResourceLoader.exists("res://assets/ui/cursors/cursor_spirit_hand.png"):
		_cursor_interact = load("res://assets/ui/cursors/cursor_spirit_hand.png") as Texture2D
	_set_cursor_mode(0)


func _set_cursor_mode(mode: int) -> void:
	if _current_cursor_mode == mode:
		return
	_current_cursor_mode = mode
	var tex: Texture2D = _cursor_normal
	if mode == 1 and _cursor_attack != null:
		tex = _cursor_attack
	elif mode == 2 and _cursor_interact != null:
		tex = _cursor_interact
	if tex != null:
		Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, Vector2(2.0, 2.0))


func _build_scene_layers() -> void:
	_audio = AudioDirector.new()
	add_child(_audio)

	# Layer 0：远景青绿云海视差底图
	var bg_canvas: CanvasLayer = CanvasLayer.new()
	bg_canvas.layer = -2
	add_child(bg_canvas)
	_parallax_bg = Sprite2D.new()
	_parallax_bg.centered = false
	if ResourceLoader.exists("res://assets/cg/title_qianli_jiangshan.png"):
		_parallax_bg.texture = load("res://assets/cg/title_qianli_jiangshan.png") as Texture2D
	_parallax_bg.scale = Vector2(1.12, 1.12)
	bg_canvas.add_child(_parallax_bg)

	# Layer 1：无缝矿物地表与道路绘制层
	_ground_layer = Node2D.new()
	add_child(_ground_layer)

	# Layer 1.5：贴地平铺器物层（地摊草席、潭面、低矮灵草——永远处于角色脚下，绝不腰斩立面人物！）
	_ground_decor_layer = Node2D.new()
	add_child(_ground_decor_layer)

	# 地面危招朱砂阵纹与走位路径层（位于地面之上、角色脚下）
	_ground_vfx = CombatVfxOverlay.new()
	_ground_vfx.is_ground_layer = true
	add_child(_ground_vfx)

	# Layer 2：核心 Y-Sort 实体深度排序层（立面建筑、古树、石碑、小队、灵宠、妖物同层排序！）
	_ysort_root = Node2D.new()
	_ysort_root.y_sort_enabled = true
	add_child(_ysort_root)

	# 空中剑气与预排连线层
	_sky_vfx = CombatVfxOverlay.new()
	_sky_vfx.is_ground_layer = false
	add_child(_sky_vfx)

	# Alt 键场景交互器物与 NPC 旧宣纸题签层（挂载在 _ysort_root 之外，z_index = 8，UNSHADED 保持高对比可读）
	_alt_nameplate_overlay = Node2D.new()
	_alt_nameplate_overlay.z_index = 8
	var np_mat: CanvasItemMaterial = CanvasItemMaterial.new()
	np_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_alt_nameplate_overlay.material = np_mat
	_alt_nameplate_overlay.draw.connect(_draw_alt_xuan_nameplates)
	add_child(_alt_nameplate_overlay)

	# Layer 3：近景斜风雨丝与区域色彩 LUT
	_rain_overlay = Node2D.new()
	_rain_overlay.z_index = 20
	_rain_overlay.draw.connect(_draw_atmosphere_rain)
	add_child(_rain_overlay)
	for _i: int in range(95):
		_rain_streaks.append(Vector2(randf_range(0.0, 2400.0), randf_range(0.0, 1400.0)))

	_mood_modulate = CanvasModulate.new()
	add_child(_mood_modulate)

	_camera = Camera2D.new()
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = int(ZONE_BOUNDS.size.x)
	_camera.limit_bottom = int(ZONE_BOUNDS.size.y)
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 7.5
	add_child(_camera)

	_combat_ctrl = RtwpCombatController.new()
	add_child(_combat_ctrl)


func _build_ui_layers() -> void:
	_ui_canvas = CanvasLayer.new()
	_ui_canvas.layer = 10
	add_child(_ui_canvas)

	_hud = CombatHud.new()
	_ui_canvas.add_child(_hud)

	_casket = DaoCasketPanel.new()
	_casket.audio_director = _audio
	_ui_canvas.add_child(_casket)

	_modals = WorldModals.new()
	_modals.audio_director = _audio
	_ui_canvas.add_child(_modals)

	_narrative = NarrativeStage.new()
	_narrative.audio_director = _audio
	_ui_canvas.add_child(_narrative)

	_recap_scroll = DefeatRecapScroll.new()
	_ui_canvas.add_child(_recap_scroll)

	_notify_overlay = NotificationOverlay.new()
	_notify_overlay.world_camera = _camera
	_ui_canvas.add_child(_notify_overlay)


func _connect_global_signals() -> void:
	InputRouter.tactical_pause_toggled.connect(func() -> void: _combat_ctrl.toggle_tactical_pause())
	InputRouter.skill_hotkey_pressed.connect(func(code: String) -> void: _combat_ctrl.trigger_hotkey_slot(code))
	InputRouter.party_select_pressed.connect(func(slot_n: int, dbl: bool) -> void: _combat_ctrl.switch_controlled_party_slot(slot_n, dbl))
	InputRouter.pet_skill_pressed.connect(func(pslot: int) -> void: _combat_ctrl.trigger_pet_manual_skill(pslot))
	InputRouter.target_tab_pressed.connect(func() -> void: _combat_ctrl.cycle_tab_enemy_target())
	InputRouter.interact_pressed.connect(_try_interact_nearest)
	InputRouter.map_toggled.connect(func() -> void:
		if _recap_scroll.visible or _narrative.visible:
			return
		if _modals.visible:
			_modals.close_modal()
		elif InputRouter.current_mode == InputRouter.MODE_WORLD_COMBAT:
			_modals.open_world_map_modal()
	)
	InputRouter.dao_casket_tab_requested.connect(func(tab_id: String) -> void:
		if _recap_scroll.visible or _narrative.visible:
			return
		if _modals.visible:
			_modals.close_modal()
		_casket.open_tab(tab_id)
	)
	InputRouter.escape_pressed.connect(_on_escape_key)
	InputRouter.alt_highlight_changed.connect(func(active: bool) -> void:
		if not active and not Input.is_key_pressed(KEY_ALT) and InputRouter.current_mode != InputRouter.MODE_WORLD_COMBAT:
			_alt_key_down = false
		_update_interact_prompt_and_cursor()
		if _alt_nameplate_overlay != null:
			_alt_nameplate_overlay.queue_redraw()
	)

	_hud.open_casket_requested.connect(func(tab_id: String) -> void:
		if _recap_scroll.visible or _narrative.visible:
			return
		_casket.open_tab(tab_id)
	)
	_hud.open_map_requested.connect(func() -> void:
		if _recap_scroll.visible or _narrative.visible:
			return
		_modals.open_world_map_modal()
	)
	_hud.open_save_modal_requested.connect(func() -> void:
		if _recap_scroll.visible or _narrative.visible:
			return
		_modals.open_save_load_modal(true)
	)
	_hud.open_settings_requested.connect(func() -> void:
		if _recap_scroll.visible or _narrative.visible:
			return
		_modals.open_settings_modal()
	)

	_casket.replay_cg_requested.connect(func(cg_id: String) -> void: _narrative.play_standalone_cg(cg_id))

	_modals.night_talk_selected.connect(func(dlg_id: String) -> void:
		_audio.play_special_bgm("res://assets/audio/bgm/bgm_night_qinglian.ogg", "night_talk")
		_narrative.start_dialogue(dlg_id, true)
	)
	_modals.stele_teleport_selected.connect(func(t_zone: String, t_spawn: String, _sid: String) -> void:
		load_zone(t_zone, t_spawn, false)
	)
	_modals.save_loaded_reload_zone.connect(func() -> void:
		load_zone(CampaignState.current_zone_id, "", true)
	)
	_modals.return_to_title_requested.connect(func() -> void:
		_set_cursor_mode(0)
		get_tree().change_scene_to_file("res://src/presentation/ui/title_screen.tscn")
	)

	_narrative.dialogue_action_triggered.connect(_execute_dialogue_action)
	_narrative.dialogue_finished.connect(_on_dialogue_finished)

	_combat_ctrl.encounter_cleared.connect(_on_encounter_cleared)
	_combat_ctrl.party_wiped.connect(func(recap: Dictionary) -> void: _recap_scroll.show_recap(recap))

	_recap_scroll.respawn_at_stele_requested.connect(_respawn_at_latest_stele)
	_recap_scroll.open_load_menu_requested.connect(func() -> void: _modals.open_save_load_modal(false))

	_notify_overlay.backup_recovery_chosen.connect(func(slot_id: String) -> void:
		var res: Dictionary = SaveManager.load_slot(slot_id, true)
		if bool(res.get("ok", false)):
			load_zone(CampaignState.current_zone_id, "", true)
	)


func _on_escape_key() -> void:
	if _narrative.visible:
		return
	if _recap_scroll.visible:
		return
	if _casket.visible:
		_casket.close_casket()
		return
	if _modals.visible:
		_modals.close_modal()
		return
	if not _hud.is_quick_drawer_open():
		_modals.open_settings_modal()
	else:
		_hud.toggle_quick_drawer()


## ==================== 三大无缝箱庭加载与装配 ====================
func load_zone(zone_id: String, spawn_tag: String = "", use_saved_pos_if_empty: bool = false) -> void:
	var epoch: int = CampaignState.bump_scene_epoch()
	CampaignState.current_zone_id = zone_id
	if spawn_tag != "":
		CampaignState.current_spawn_tag = spawn_tag
	if _rain_overlay != null:
		_rain_overlay.queue_redraw()

	NotifyHub.clear_all_transient()
	for ch: Node in _ground_layer.get_children():
		ch.queue_free()
	for ch_d: Node in _ground_decor_layer.get_children():
		ch_d.queue_free()
	for ch2: Node in _ysort_root.get_children():
		ch2.queue_free()

	_ground_base_sub = Node2D.new()
	_road_feather_sub = Node2D.new()
	_road_stone_sub = Node2D.new()
	_road_curb_sub = Node2D.new()
	_ground_layer.add_child(_ground_base_sub)
	_ground_layer.add_child(_road_feather_sub)
	_ground_layer.add_child(_road_stone_sub)
	_ground_layer.add_child(_road_curb_sub)

	_occluder_sprites.clear()
	_interactables.clear()
	_zone_portals.clear()
	_portal_markers.clear()
	_npc_actors.clear()
	_zone_point_lights.clear()
	_wet_road_materials.clear()
	_hovered_interactable_id = ""
	_mm_roads.clear()
	_mm_buildings.clear()
	_mm_steles.clear()
	_mm_portals.clear()
	_combat_ctrl.reset_for_zone(_ysort_root, _ground_vfx, _sky_vfx, _camera, _audio)
	if _alt_nameplate_overlay != null:
		_alt_nameplate_overlay.queue_redraw()

	var spawn_pos: Vector2 = CampaignState.saved_player_pos if (spawn_tag == "" and use_saved_pos_if_empty) else _get_spawn_coords(zone_id, spawn_tag)

	match zone_id:
		"tingyu_town":
			_assemble_tingyu_town()
			_mood_modulate.color = Color(0.76, 0.81, 0.84, 1.0)
			_parallax_bg.modulate = Color(0.75, 0.82, 0.80, 1.0)
			_audio.start_qinglan_dual_stem(true)
		"qinglan_pass":
			_assemble_qinglan_pass()
			_mood_modulate.color = Color(0.74, 0.80, 0.83, 1.0)
			_parallax_bg.modulate = Color(0.62, 0.70, 0.72, 1.0)
			_audio.start_qinglan_dual_stem(true)
		"cangmu_cave":
			_assemble_cangmu_cave()
			_mood_modulate.color = Color(0.70, 0.76, 0.76, 1.0)
			_parallax_bg.modulate = Color(0.28, 0.34, 0.32, 1.0)
			_audio.start_qinglan_dual_stem(false)

	_combat_ctrl.spawn_party_at(spawn_pos)
	_camera.position = spawn_pos
	_rebuild_foreground_bamboo_leaves(zone_id != "cangmu_cave")
	_sync_foreground_bamboo_positions(0.0)
	_hud.bind_combat_controller(_combat_ctrl)
	_hud.set_minimap_zone_geometry(_mm_roads, _mm_buildings, _mm_steles, _mm_portals, _npc_actors)
	InputRouter.set_mode(InputRouter.MODE_WORLD_COMBAT)

	# 新开局入镇自动触发雨中独白（带纪元守卫防残留！）
	if zone_id == "tingyu_town" and not CampaignState.read_dialogues.has("dlg_ch01_opening_rain"):
		get_tree().create_timer(0.45).timeout.connect(func() -> void:
			if CampaignState.scene_epoch == epoch:
				_narrative.start_dialogue("dlg_ch01_opening_rain")
		)


func _get_spawn_coords(zone_id: String, spawn_tag: String) -> Vector2:
	match zone_id:
		"tingyu_town":
			if spawn_tag == "from_pass":
				return Vector2(2110.0, 605.0)
			if spawn_tag == "stele_tingyu_gate":
				return Vector2(1855.0, 645.0)
			return Vector2(360.0, 790.0)
		"qinglan_pass":
			if spawn_tag == "from_cave":
				return Vector2(1950.0, 645.0)
			if spawn_tag == "stele_temple_courtyard":
				return Vector2(1725.0, 645.0)
			return Vector2(220.0, 960.0)
		"cangmu_cave":
			if spawn_tag == "stele_cave_mid":
				return Vector2(1290.0, 775.0)
			if spawn_tag == "stele_wolf_altar":
				return Vector2(1680.0, 570.0)
			return Vector2(240.0, 1090.0)
	return Vector2(400.0, 700.0)


## ==================== 区域 ①：听雨镇 & 济世药庐外院 ====================
func _assemble_tingyu_town() -> void:
	_add_tiled_ground("res://assets/world/tex_moss_earth.png", ZONE_BOUNDS)

	# 1. 35° 斜向青石药庐内院大坪 + 茶寮至散修斜切顺滑连坪（消除生硬 90° 直角折弯） + 蜿蜒湿青石主街（挂载受光 wet_bluestone.gdshader！）
	_add_road_polygon(PackedVector2Array([
		Vector2(916.0, 620.0), Vector2(1340.0, 416.0), Vector2(1742.0, 607.0), Vector2(1336.0, 822.0)
	]), "res://assets/world/tex_bluestone_wet.png")
	_add_road_polygon(PackedVector2Array([
		Vector2(382.0, 560.0), Vector2(722.0, 550.0), Vector2(974.0, 704.0),
		Vector2(1024.0, 902.0), Vector2(666.0, 926.0), Vector2(368.0, 778.0)
	]), "res://assets/world/tex_bluestone_wet.png")
	_add_road_polygon(PackedVector2Array([
		Vector2(-180.0, 748.0), Vector2(420.0, 718.0), Vector2(740.0, 710.0), Vector2(928.0, 702.0),
		Vector2(1148.0, 792.0), Vector2(1336.0, 866.0), Vector2(1318.0, 988.0),
		Vector2(1084.0, 954.0), Vector2(740.0, 916.0), Vector2(410.0, 910.0), Vector2(-180.0, 922.0)
	]), "res://assets/world/tex_bluestone_wet.png")
	_add_road_polygon(PackedVector2Array([
		Vector2(1298.0, 854.0), Vector2(1545.0, 736.0), Vector2(1772.0, 626.0), Vector2(2040.0, 544.0),
		Vector2(2580.0, 488.0), Vector2(2580.0, 702.0), Vector2(2045.0, 768.0),
		Vector2(1822.0, 846.0), Vector2(1560.0, 938.0), Vector2(1318.0, 988.0)
	]), "res://assets/world/tex_bluestone_wet.png")
	# 街南朝北迎街民居的连续青石街沿踏跺带（顺应 35° 聚落走势自然衔接三户门廊，消除零碎垂直锯齿支巷！）
	_add_road_polygon(PackedVector2Array([
		Vector2(152.0, 908.0), Vector2(420.0, 906.0), Vector2(740.0, 912.0), Vector2(1018.0, 944.0),
		Vector2(968.0, 1142.0), Vector2(592.0, 1086.0), Vector2(174.0, 1018.0)
	]), "res://assets/world/tex_bluestone_wet.png")

	# 2. 左街（x < 965）南北夹街宋明工笔粉墙黛瓦民居群：街北朝南临街，街南采用朝北迎街的粉墙花窗与徽派马头墙民居（退界舒展、朝向自洽！）
	_add_ysort_structure("res://assets/world/prop_folk_house_b.png", Vector2(204.0, 542.0), 52.0, true)
	_add_ysort_structure("res://assets/world/prop_folk_house_a.png", Vector2(428.0, 524.0), 52.0, true)
	_add_ysort_structure("res://assets/world/prop_folk_house_a.png", Vector2(226.0, 724.0), 58.0, true)
	_add_ysort_structure("res://assets/world/prop_tea_pavilion.png", Vector2(576.0, 654.0), 84.0, true)
	_add_ysort_structure("res://assets/world/prop_folk_roof_eave.png", Vector2(258.0, 1162.0), 64.0, true)
	_add_ysort_structure("res://assets/world/prop_folk_house_south.png", Vector2(614.0, 1218.0), 62.0, true)
	_add_ysort_structure("res://assets/world/prop_folk_house_south.png", Vector2(956.0, 1272.0), 62.0, true)

	# 3. 右侧全闭合真 35° 斜向围合式【济世药庐】院落（与正堂、丹亭、长街共享统一 35° 轴测透视，对标 master_a_tingyu_town.png！）
	_add_ground_decor_prop("res://assets/world/prop_yaolu_alchemy_terrace.png", Vector2(1406.0, 692.0), "YaoluAlchemyTerrace")
	_add_ysort_structure("res://assets/world/prop_yaolu_hall.png", Vector2(1192.0, 606.0), 85.0, true)
	_add_ysort_structure("res://assets/world/prop_yaolu_alchemy_pavilion.png", Vector2(1306.0, 688.0), 0.0, true)

	# 西北与东北内院背墙 + 西南临街粉墙门楼 + 南转角院墙 + 东南粉墙（短模块中心锚定 + 96px 严丝合缝搭接，0 断缝、0 斜墙腰斩！）
	_add_ysort_wall_module("res://assets/world/prop_yaolu_courtyard_wall.png", Vector2(968.0, 594.0), false, -108.0)
	_add_ysort_wall_module("res://assets/world/prop_yaolu_courtyard_wall.png", Vector2(1064.0, 542.0), false, -108.0)
	_add_ysort_wall_module("res://assets/world/prop_yaolu_courtyard_wall.png", Vector2(972.0, 648.0), true, -108.0)
	_add_ysort_wall_module("res://assets/world/prop_yaolu_gatehouse.png", Vector2(1134.0, 728.0), false, -228.0)
	_add_ysort_wall_module("res://assets/world/prop_yaolu_side_wall.png", Vector2(1336.0, 822.0), false, -149.0)
	_add_ysort_wall_module("res://assets/world/prop_yaolu_courtyard_wall.png", Vector2(1456.0, 756.0), false, -108.0)
	_add_ysort_wall_module("res://assets/world/prop_yaolu_courtyard_wall.png", Vector2(1552.0, 704.0), false, -108.0)
	_add_ysort_wall_module("res://assets/world/prop_yaolu_courtyard_wall.png", Vector2(1648.0, 652.0), false, -108.0)
	_add_ysort_wall_module("res://assets/world/prop_yaolu_courtyard_wall.png", Vector2(1708.0, 620.0), false, -108.0)
	_add_ysort_wall_module("res://assets/world/prop_yaolu_courtyard_wall.png", Vector2(1692.0, 578.0), true, -108.0)
	_add_ysort_wall_module("res://assets/world/prop_yaolu_courtyard_wall.png", Vector2(1596.0, 526.0), true, -108.0)

	_append_wall_segment_obstacles(Vector2(916.0, 620.0), Vector2(1118.0, 518.0), 26.0, 24.0)
	_append_wall_segment_obstacles(Vector2(916.0, 620.0), Vector2(1080.0, 702.0), 26.0, 24.0)
	_append_wall_segment_obstacles(Vector2(1192.0, 758.0), Vector2(1336.0, 822.0), 26.0, 24.0)
	_append_wall_segment_obstacles(Vector2(1336.0, 822.0), Vector2(1742.0, 607.0), 26.0, 24.0)
	_append_wall_segment_obstacles(Vector2(1742.0, 607.0), Vector2(1532.0, 500.0), 26.0, 24.0)

	# 4. 古樟树、太湖苔石假山与净透翠竹簇（保留 Vector2(835, 595) 香樟门禁；假山与街南民居留出舒适间距）
	_add_ysort_structure("res://assets/world/prop_camphor_tree.png", Vector2(835.0, 595.0), 52.0, true)
	_add_ysort_structure("res://assets/world/prop_camphor_tree.png", Vector2(1818.0, 560.0), 52.0, true)
	_add_ysort_structure("res://assets/world/prop_bamboo_cluster.png", Vector2(128.0, 565.0), 38.0, true)
	_add_ysort_structure("res://assets/world/prop_bamboo_cluster.png", Vector2(2152.0, 886.0), 46.0, true)
	_add_ysort_structure("res://assets/world/prop_bamboo_cluster.png", Vector2(88.0, 1286.0), 38.0, true)
	_add_ysort_structure("res://assets/world/prop_town_rockery.png", Vector2(442.0, 1196.0), 34.0, false)
	_add_ysort_structure("res://assets/world/prop_town_rockery.png", Vector2(1208.0, 1236.0), 34.0, false)
	_add_ysort_structure("res://assets/world/prop_town_rockery.png", Vector2(1742.0, 962.0), 34.0, false)

	# 5. 专属城镇 NPC 序列帧（老樵夫于茶寮檐口避雨歇脚 / 散修退立席后不踩器物 / 沈清禾立于门侧让出敞门 / 周执事立于东柱外侧零遮挡）
	_spawn_npc("npc_elder", "听雨镇老樵夫", "npc_elder", Vector2(568.0, 668.0), "tea_elder")

	var ped_a: BattleActor = _spawn_npc("npc_peddler", "游方摆摊散修", "npc_peddler", Vector2(832.0, 756.0), "peddler")
	if ped_a != null:
		ped_a.set_facing(Vector2(0.68, 0.73))
	_combat_ctrl.obstacle_circles.append({"pos": Vector2(832.0, 746.0), "radius": 34.0})
	_add_interactable("peddler_stall", "stall", Vector2(852.0, 908.0), 144.0, "散修小地摊 [F 掌眼淘旧物]", "res://assets/world/prop_peddler_stall.png", -1, true)

	if not bool(CampaignState.world_flags.get("met_shen_qinghe", false)):
		# 沈清禾立于柴门右侧檐灯旁青石迎诊位（y=774 > 门楼 y=728，全身 100% 零遮挡，且完整让出敞开柴门通道！）
		var shen_a: BattleActor = _spawn_npc("shen_npc", "沈清禾 · 药庐医修", "shen_qinghe", Vector2(1206.0, 774.0), "meet_shen")
		if shen_a != null:
			shen_a.set_facing(Vector2(-0.68, 0.73))

	# 药庐外院实体器物三件套：青铜丹炉 + 内推避墙药肆木柜 + 无遮挡弃置废丹竹篓
	var furnace_obs: int = _combat_ctrl.obstacle_circles.size()
	_combat_ctrl.obstacle_circles.append({"pos": Vector2(1405.0, 610.0), "radius": 52.0})
	_add_interactable("yaolu_alchemy", "alchemy", Vector2(1405.0, 646.0), 158.0, "济世青铜丹炉 [F 控火炼丹]", "res://assets/world/prop_alchemy_furnace.png", furnace_obs)

	var counter_obs: int = _combat_ctrl.obstacle_circles.size()
	_combat_ctrl.obstacle_circles.append({"pos": Vector2(1090.0, 594.0), "radius": 40.0})
	_add_interactable("yaolu_shop", "shop", Vector2(1090.0, 624.0), 152.0, "药庐外院药肆 [F 购草寄售]", "res://assets/world/prop_yaolu_counter.png", counter_obs)

	if not CampaignState.opened_containers.has("yaolu_discarded_pill"):
		_add_interactable("yaolu_discarded_pill", "burnt_pill_pickup", Vector2(1636.0, 588.0), 132.0, "丹炉旁弃置药篓 [F 翻检废丹]", "res://assets/world/prop_discarded_pill_basket.png")

	if not bool(CampaignState.world_flags.get("yaolu_spy_resolved", false)):
		var zhou_a: BattleActor = _spawn_npc("npc_zhou", "药庐周执事", "npc_steward_zhou", Vector2(1572.0, 604.0), "steward_zhou")
		if zhou_a != null:
			zhou_a.set_facing(Vector2(-0.82, 0.57))

	# 灵草采集点 1（完整工笔石绿灵叶丛，设于街南岩竹坡畔）
	if not CampaignState.opened_containers.has("herb_town_1"):
		_add_interactable("herb_town_1", "herb", Vector2(1525.0, 995.0), 96.0, "青木灵叶丛 [F 采摘]", "res://assets/world/prop_spirit_herb_node.png", -1, true)

	# 镇口引灵石碑设于东南官道路台 (1896, 768)，即使南行拉低镜头亦完全处于右上角小地图面板下方零叠压！
	var stele_obs: int = _combat_ctrl.obstacle_circles.size()
	_combat_ctrl.obstacle_circles.append({"pos": Vector2(1896.0, 744.0), "radius": 40.0})
	_add_interactable("stele_tingyu_gate", "stele", Vector2(1896.0, 768.0), 156.0, "听雨镇驿口 · 引灵石碑 [F 休整/夜话/传送]", "res://assets/world/prop_stele_lit.png", stele_obs)

	# Stage C 动态暖/冷光源（每盏均精准锚定实体灯笼/丹炉/石碑发光体，全区严格 5 盏 <= 8 盏/屏）
	_add_stage_c_point_light(Vector2(606.0, 658.0), Color(0.96, 0.68, 0.34, 1.0), 0.50, 1.62, 0.4)
	_add_stage_c_point_light(Vector2(887.0, 798.0), Color(0.95, 0.66, 0.32, 1.0), 0.46, 1.45, 1.7)
	_add_stage_c_point_light(Vector2(1196.0, 724.0), Color(0.96, 0.68, 0.34, 1.0), 0.48, 1.48, 2.9)
	_add_stage_c_point_light(Vector2(1385.0, 642.0), Color(1.00, 0.60, 0.20, 1.0), 1.52, 2.75, 4.1)
	_add_stage_c_point_light(Vector2(1896.0, 750.0), Color(0.32, 0.84, 0.76, 1.0), 0.58, 1.88, -1.0)

	# 东北出镇官道 -> 风雨青岚山道
	_add_zone_portal(Rect2(2265.0, 505.0, 130.0, 210.0), "qinglan_pass", "from_town", "北出听雨镇 ──▶ 风雨青岚山道")


## ==================== 区域 ②：风雨青岚山道 & 破庙庭院 ====================
func _assemble_qinglan_pass() -> void:
	_add_tiled_ground("res://assets/world/tex_moss_earth.png", ZONE_BOUNDS)
	# 两道横断山涧飞泉深壑（绘于道路下层，由两座杉木栈桥严丝合缝跨越天堑！）
	_build_pass_mountain_ravines()

	# 三段被山涧隔开的山道青石路 + 东南临渊观景支路（桥头精准对接栈桥青石桥台，挂载 wet_bluestone.gdshader！）
	_add_road_polygon(PackedVector2Array([
		Vector2(60, 900), Vector2(720, 820), Vector2(888, 762),
		Vector2(922, 876), Vector2(760, 990), Vector2(60, 1060)
	]), "res://assets/world/tex_bluestone_wet.png")
	_add_road_polygon(PackedVector2Array([
		Vector2(1062, 704), Vector2(1296, 624),
		Vector2(1332, 738), Vector2(1098, 818)
	]), "res://assets/world/tex_bluestone_wet.png")
	_add_road_polygon(PackedVector2Array([
		Vector2(1474, 566), Vector2(1620, 560), Vector2(2210, 560),
		Vector2(2210, 710), Vector2(1650, 715), Vector2(1506, 682)
	]), "res://assets/world/tex_bluestone_wet.png")
	_add_road_polygon(PackedVector2Array([
		Vector2(1245, 725), Vector2(1395, 755), Vector2(1450, 920), Vector2(1310, 930)
	]), "res://assets/world/tex_bluestone_wet.png")

	# 东南云海断崖深渊与对岸孤峰古修秘匣（物理阻断不可徒步跨越，彻底自洽“百丈绝壁金丹御剑”伏笔！）
	_build_pass_cliff_abyss()

	# M4 山道临渊杉木栈桥（跨越东西两道山涧深壑，桥台严丝合缝搭接两岸青石路肩，并以苔石奇峰压边收口！）
	_add_ground_decor_prop("res://assets/world/prop_mountain_plank_bridge.png", Vector2(978.0, 874.0), "PassPlankBridgeWest")
	_add_ground_decor_prop("res://assets/world/prop_mountain_plank_bridge.png", Vector2(1388.0, 734.0), "PassPlankBridgeEast")
	_add_ysort_structure("res://assets/world/prop_town_rockery.png", Vector2(902.0, 916.0), 0.0, false)
	_add_ysort_structure("res://assets/world/prop_town_rockery.png", Vector2(1078.0, 710.0), 0.0, false)
	_add_ysort_structure("res://assets/world/prop_town_rockery.png", Vector2(1312.0, 774.0), 0.0, false)
	_add_ysort_structure("res://assets/world/prop_town_rockery.png", Vector2(1488.0, 568.0), 0.0, false)

	# 掩体巨石（支持魔兽式卡远程法怪视野 Pulling！）与 M4 苍翠竹海（>= 7 处竹丛）+ 破庙
	_add_ysort_structure("res://assets/world/prop_cliff_rock.png", Vector2(690.0, 740.0), 68.0, false)
	_add_ysort_structure("res://assets/world/prop_cliff_rock.png", Vector2(1220.0, 560.0), 68.0, false)
	_add_ysort_structure("res://assets/world/prop_camphor_tree.png", Vector2(520.0, 430.0), 58.0, true)
	_add_ysort_structure("res://assets/world/prop_bamboo_cluster.png", Vector2(205.0, 835.0), 0.0, true)
	_add_ysort_structure("res://assets/world/prop_bamboo_cluster.png", Vector2(415.0, 805.0), 0.0, true)
	_add_ysort_structure("res://assets/world/prop_bamboo_cluster.png", Vector2(885.0, 625.0), 0.0, true)
	_add_ysort_structure("res://assets/world/prop_bamboo_cluster.png", Vector2(1060.0, 880.0), 52.0, true)
	_add_ysort_structure("res://assets/world/prop_bamboo_cluster.png", Vector2(1215.0, 930.0), 52.0, true)
	_add_ysort_structure("res://assets/world/prop_bamboo_cluster.png", Vector2(1515.0, 515.0), 0.0, true)
	_add_ysort_structure("res://assets/world/prop_bamboo_cluster.png", Vector2(2115.0, 495.0), 0.0, true)
	_add_ysort_structure("res://assets/world/prop_ruined_temple.png", Vector2(1890.0, 515.0), 115.0, true)

	# 支线 ②：古樟下救护受瘴幼兽契约初生灵宠（火狐 / 灵龟二选一）
	if CampaignState.active_pet_id == "":
		_add_interactable("injured_beast", "beast_rescue", Vector2(560.0, 495.0), 105.0, "受瘴哀鸣的通灵幼兽 [F 施药救治契宠]", "res://assets/world/prop_spirit_herb_node.png", -1, true)

	# 临渊观景石台（对岸孤峰石匣在 _build_pass_cliff_abyss 中隔渊陈列）
	_add_interactable("cliff_chest_vista", "cliff_vista", Vector2(1385.0, 895.0), 110.0, "临渊远眺绝壁对岸的古修石匣 [F]", "")

	# 山道采集点
	if not CampaignState.opened_containers.has("herb_pass_1"):
		_add_interactable("herb_pass_1", "herb_fire", Vector2(880.0, 470.0), 85.0, "雷击木赤阳火芝 [F 采摘]", "res://assets/world/prop_spirit_herb_node.png", -1, true)

	# 明雷敌群 1：山道前段巡逻腐爪妖狼 + 瘴林毒巫（读条怪，练习 Tab+Q 打断与拉怪！）
	if not CampaignState.cleared_encounters.has("enc_pass_pack_1"):
		_combat_ctrl.spawn_enemy_unit("rot_wolf", Vector2(780.0, 860.0), "enc_pass_pack_1", [Vector2(740.0, 860.0), Vector2(920.0, 790.0)])
		_combat_ctrl.spawn_enemy_unit("miasma_shaman", Vector2(860.0, 890.0), "enc_pass_pack_1")

	if not CampaignState.cleared_encounters.has("enc_pass_pack_2"):
		_combat_ctrl.spawn_enemy_unit("rot_wolf", Vector2(1355.0, 655.0), "enc_pass_pack_2")
		_combat_ctrl.spawn_enemy_unit("rot_wolf", Vector2(1405.0, 685.0), "enc_pass_pack_2")

	# 破庙前庭引灵石碑（未点亮时为苍苔暗刻石碑，点亮后绽放青莲灵纹）
	var temple_stele_lit: bool = CampaignState.unlocked_steles.has("stele_temple_courtyard")
	_add_interactable(
		"stele_temple_courtyard", "stele", Vector2(1655.0, 610.0), 105.0,
		"青岚破庙前庭 · 引灵石碑 [F 休整/夜话/传送]",
		"res://assets/world/prop_stele_lit.png" if temple_stele_lit else "res://assets/world/prop_stele_dim.png"
	)

	# Stage C 动态暖/冷光源（全区严格 4 盏 <= 8 盏/屏）
	_add_stage_c_point_light(Vector2(560.0, 495.0), Color(0.45, 0.88, 0.78, 1.0), 0.72, 1.95, -1.0)
	_add_stage_c_point_light(Vector2(985.0, 795.0), Color(0.98, 0.66, 0.30, 1.0), 0.82, 2.15, 1.1)
	_add_stage_c_point_light(Vector2(1655.0, 600.0), Color(0.38, 0.90, 0.82, 1.0), 0.94, 2.15, -1.0)
	_add_stage_c_point_light(Vector2(1890.0, 560.0), Color(0.98, 0.64, 0.28, 1.0), 0.86, 2.05, 2.6)

	# 破庙主事件或地底古窟入口
	if not bool(CampaignState.world_flags.get("met_pei_zhao", false)):
		_add_interactable("temple_event_trigger", "temple_clash", Vector2(1890.0, 640.0), 145.0, "踏入【青岚破庙】查探狼啸异变 [F]", "")
	elif CampaignState.cleared_encounters.has("enc_temple_wolves"):
		_add_zone_portal(Rect2(2060.0, 565.0, 150.0, 130.0), "cangmu_cave", "from_pass", "破庙地脉石阶 ──▶ 苍木灵枢古窟")

	_add_zone_portal(Rect2(10.0, 870.0, 120.0, 220.0), "tingyu_town", "from_pass", "◀── 南返听雨镇")


## ==================== 区域 ③：苍木灵枢古窟（三段回环五行秘境 + 雾隐狼王） ====================
func _assemble_cangmu_cave() -> void:
	_add_tiled_ground("res://assets/world/tex_cave_flagstone.png", ZONE_BOUNDS)
	# 1. 四段自然斜切地底古窟岩板洞室（专属地底无缝石灰岩铺地 tex_cave_pathway.png，完整覆盖北侧潜行石室、南侧泉窟与八卦首领祭坛，消除窄条拼接与小地图悬空！）
	_add_road_polygon(PackedVector2Array([
		Vector2(60, 1018), Vector2(410, 1008), Vector2(815, 1002), Vector2(1235, 675),
		Vector2(1625, 428), Vector2(1840, 368), Vector2(2190, 362), Vector2(2320, 445),
		Vector2(2310, 625), Vector2(2095, 665), Vector2(1745, 642), Vector2(1335, 835),
		Vector2(890, 1152), Vector2(430, 1162), Vector2(60, 1165)
	]), "res://assets/world/tex_cave_pathway.png")
	_add_road_polygon(PackedVector2Array([
		Vector2(422, 1030), Vector2(418, 742), Vector2(482, 672), Vector2(1275, 668),
		Vector2(1275, 782), Vector2(578, 786), Vector2(552, 822), Vector2(556, 1030)
	]), "res://assets/world/tex_cave_pathway.png")
	_add_road_polygon(PackedVector2Array([
		Vector2(768, 695), Vector2(736, 515), Vector2(748, 256), Vector2(822, 184),
		Vector2(1148, 184), Vector2(1224, 258), Vector2(1232, 512), Vector2(1196, 695)
	]), "res://assets/world/tex_cave_pathway.png")
	_add_road_polygon(PackedVector2Array([
		Vector2(855, 1068), Vector2(1325, 1086), Vector2(1412, 1138),
		Vector2(1392, 1236), Vector2(1140, 1252), Vector2(868, 1202)
	]), "res://assets/world/tex_cave_pathway.png")

	# 2. 地底斧劈皴玄岩实体山壁（彻底封死毒棘墙与回环石门两侧，消除直角黑块与亮青描边，严禁室外香樟树与竹丛！）
	_add_cavern_rock_mass(PackedVector2Array([
		Vector2(0, 0), Vector2(690, 0), Vector2(685, 608), Vector2(438, 648), Vector2(380, 712), Vector2(380, 975), Vector2(0, 975)
	]))
	_add_cavern_rock_mass(PackedVector2Array([
		Vector2(600, 815), Vector2(718, 808), Vector2(742, 892), Vector2(735, 985), Vector2(600, 985)
	]))
	_add_cavern_rock_mass(PackedVector2Array([
		Vector2(0, 1205), Vector2(760, 1205), Vector2(900, 1292), Vector2(1455, 1288),
		Vector2(1560, 920), Vector2(1748, 682), Vector2(2140, 688), Vector2(2400, 648), Vector2(2400, 1400), Vector2(0, 1400)
	]))
	_add_cavern_rock_mass(PackedVector2Array([
		Vector2(690, 0), Vector2(2400, 0), Vector2(2400, 322), Vector2(1820, 332), Vector2(1660, 352),
		Vector2(1385, 535), Vector2(1272, 535), Vector2(1258, 218), Vector2(1182, 148), Vector2(768, 148), Vector2(690, 218)
	]))

	# 3. 八卦首领古祭坛地坪（对标 master_b_cangmu_rtwp.png）与宋明工笔青苔石阶
	_add_ground_decor_prop("res://assets/world/prop_cave_bagua_altar.png", Vector2(1985.0, 628.0), "CaveBossBaguaAltar")
	_add_ground_decor_prop("res://assets/world/prop_cave_stone_steps.png", Vector2(1078.0, 932.0), "CaveStoneStepsMid")
	_add_ground_decor_prop("res://assets/world/prop_cave_stone_steps.png", Vector2(1485.0, 622.0), "CaveStoneStepsAltar")

	# 4. 扎根苔石的巨型盘根古木（开启 55% 半透遮挡）+ 顺应 35° 斜壁走势的立面洞壁与石笋群（双侧石墩嵌合回环石门，零遮挡门洞！）
	_add_ysort_structure("res://assets/world/prop_cave_gnarled_roots.png", Vector2(242.0, 968.0), 38.0, true)
	_add_ysort_structure("res://assets/world/prop_cave_gnarled_roots.png", Vector2(716.0, 382.0), 0.0, true)
	_add_ysort_structure("res://assets/world/prop_cave_gnarled_roots.png", Vector2(1435.0, 498.0), 38.0, true)
	_add_ysort_structure("res://assets/world/prop_cave_gnarled_roots.png", Vector2(1965.0, 366.0), 38.0, true)

	_add_ysort_structure("res://assets/world/prop_cave_cliff_wall.png", Vector2(1528.0, 446.0), 0.0, false)
	_add_ysort_structure("res://assets/world/prop_cave_cliff_wall.png", Vector2(1748.0, 362.0), 0.0, false)

	_add_ysort_structure("res://assets/world/prop_cave_stalagmite.png", Vector2(382.0, 876.0), 0.0, false)
	_add_ysort_structure("res://assets/world/prop_cave_stalagmite.png", Vector2(604.0, 878.0), 0.0, false)
	_add_ysort_structure("res://assets/world/prop_cave_stalagmite.png", Vector2(692.0, 616.0), 0.0, false)
	_add_ysort_structure("res://assets/world/prop_cave_stalagmite.png", Vector2(978.0, 178.0), 0.0, false)
	_add_ysort_structure("res://assets/world/prop_cave_stalagmite.png", Vector2(1286.0, 548.0), 0.0, false)
	_add_ysort_structure("res://assets/world/prop_cave_stalagmite.png", Vector2(1562.0, 928.0), 0.0, false)
	_add_ysort_structure("res://assets/world/prop_cave_stalagmite.png", Vector2(2215.0, 362.0), 0.0, false)

	_add_ysort_structure("res://assets/world/prop_cliff_rock.png", Vector2(698.0, 936.0), 44.0, false)
	_add_ysort_structure("res://assets/world/prop_cliff_rock.png", Vector2(1322.0, 520.0), 48.0, false)
	_add_ysort_structure("res://assets/world/prop_cliff_rock.png", Vector2(1612.0, 342.0), 48.0, false)

	# 5. 实体雕纹石火盆（独立立于石门南侧与祭坛阶侧零遮挡位，精准托举洞窟暖色炭火 PointLight2D！）
	_add_ysort_structure("res://assets/world/prop_cave_stone_brazier.png", Vector2(384.0, 1006.0), 22.0, false)
	_add_ysort_structure("res://assets/world/prop_cave_stone_brazier.png", Vector2(598.0, 962.0), 0.0, false)
	_add_ysort_structure("res://assets/world/prop_cave_stone_brazier.png", Vector2(1832.0, 390.0), 22.0, false)

	# 五行禁制 ①：火焚腐瘴毒棘墙（严密卡死主通道咽喉 x=640,y=1085，未焚毁前 100% 不可通行！）
	if not bool(CampaignState.world_flags.get("vine_wall_burned", false)):
		var obs_idx: int = _combat_ctrl.obstacle_circles.size()
		_combat_ctrl.obstacle_circles.append({"pos": Vector2(640.0, 1085.0), "radius": 96.0})
		_add_interactable("barrier_vine", "fire_barrier", Vector2(640.0, 1085.0), 145.0, "【五行禁制】腐瘴毒棘墙 [按 F 引真火焚毁]", "res://assets/world/prop_vine_barrier.png", obs_idx)

	# 北侧【敛息符】越级潜行偷草岔路：巡逻守窟木傀在南侧 y=430 镇守，与北侧 y=235 秘匣拉开 195px 纵深绝不重叠！
	if not CampaignState.cleared_encounters.has("enc_cave_golem"):
		_combat_ctrl.spawn_enemy_unit("wood_golem", Vector2(980.0, 430.0), "enc_cave_golem", [Vector2(845.0, 430.0), Vector2(1115.0, 430.0)])
	if not CampaignState.opened_containers.has("herb_cave_stealth"):
		_add_interactable("herb_cave_stealth", "herb_corrupt", Vector2(835.0, 235.0), 90.0, "腐骨幽花丛 [F 屏息采摘]", "res://assets/world/prop_spirit_herb_node.png", -1, true)
	if not CampaignState.opened_containers.has("chest_poxue_pendant"):
		_add_interactable("chest_poxue_pendant", "chest_poxue", Vector2(1125.0, 235.0), 95.0, "古修秘藏石匣 [F 开启]", "res://assets/world/prop_treasure_chest.png")

	# 南侧五行禁制 ②：水净瘴池（贴地层，不遮挡人物） & 坐化古修遗骸
	var pool_clean: bool = bool(CampaignState.world_flags.get("miasma_pool_cleansed", false))
	_add_interactable(
		"barrier_pool", "water_barrier", Vector2(1120.0, 1155.0), 125.0,
		"清冽灵泉池" if pool_clean else "【五行禁制】死水腐瘴潭 [按 F 唤沈清禾玄水净池]",
		"res://assets/world/prop_miasma_pool_clean.png" if pool_clean else "res://assets/world/prop_miasma_pool.png",
		-1, true
	)
	_add_interactable("ancient_remains", "remains", Vector2(1310.0, 1165.0), 105.0, "百年前坐化古修遗骸 [F 参悟遗刻]", "res://assets/world/prop_ancient_remains.png")

	# 古窟中段明雷群（拉开 135px 横向站位间距，使双怪头顶姓名血条清晰并列零叠压！）
	if not CampaignState.cleared_encounters.has("enc_cave_pack_1"):
		_combat_ctrl.spawn_enemy_unit("rot_wolf", Vector2(900.0, 1005.0), "enc_cave_pack_1")
		_combat_ctrl.spawn_enemy_unit("miasma_shaman", Vector2(1035.0, 975.0), "enc_cave_pack_1")

	# 回环捷径石门（设在 x=490,y=885 竖直近路咽喉，两侧连接实体岩壁，须从北侧内廊开启！）
	var gate_open: bool = bool(CampaignState.world_flags.get("shortcut_gate_opened", false))
	var gate_obs: int = -1
	if not gate_open:
		gate_obs = _combat_ctrl.obstacle_circles.size()
		_combat_ctrl.obstacle_circles.append({"pos": Vector2(490.0, 885.0), "radius": 96.0})
	_add_interactable(
		"shortcut_gate", "shortcut_gate", Vector2(490.0, 885.0), 135.0,
		"回环捷径石门（已贯通）" if gate_open else "古窟回环机关石门 [F 自北侧内廊开启]",
		"res://assets/world/prop_cave_arch_gate.png", gate_obs
	)

	# 中枢石碑与首领祭坛门前石碑（首领门前必设石碑铁律！）
	_add_interactable(
		"stele_cave_mid", "stele", Vector2(1290.0, 725.0), 105.0,
		"苍木古窟中枢 · 引灵石碑 [F 休整/夜话/传送]",
		"res://assets/world/prop_stele_lit.png" if CampaignState.unlocked_steles.has("stele_cave_mid") else "res://assets/world/prop_stele_dim.png"
	)
	_add_interactable(
		"stele_wolf_altar", "stele", Vector2(1650.0, 505.0), 105.0,
		"灵枢祭坛门前 · 引灵石碑 [F 战前休整/夜话]",
		"res://assets/world/prop_stele_lit.png" if CampaignState.unlocked_steles.has("stele_wolf_altar") else "res://assets/world/prop_stele_dim.png"
	)

	# Stage C 地底动态暖/冷光源（全区严格 6 盏 <= 8 盏/屏，暖光全部锚定石火盆火芯，冷光锚定石碑与灵池！）
	_add_stage_c_point_light(Vector2(384.0, 950.0), Color(0.98, 0.62, 0.26, 1.0), 0.84, 2.00, 0.7)
	_add_stage_c_point_light(Vector2(598.0, 906.0), Color(0.96, 0.62, 0.28, 1.0), 0.78, 1.92, 2.1)
	_add_stage_c_point_light(Vector2(1832.0, 336.0), Color(0.98, 0.60, 0.24, 1.0), 0.78, 1.95, 3.4)
	_add_stage_c_point_light(Vector2(1120.0, 1145.0), Color(0.36, 0.86, 0.82, 1.0), 0.82, 2.05, -1.0)
	_add_stage_c_point_light(Vector2(1290.0, 715.0), Color(0.38, 0.90, 0.82, 1.0), 0.95, 2.20, -1.0)
	_add_stage_c_point_light(Vector2(1650.0, 505.0), Color(0.38, 0.92, 0.84, 1.0), 1.04, 2.30, -1.0)

	# 章节双阶段主首领：【雾隐狼王】（镇守八卦古祭坛 x=2025,y=545，远离右上角小地图遮挡，踏上 x=1875 祭坛即触发对峙！）
	if not bool(CampaignState.world_flags.get("wolf_king_defeated", false)):
		var boss: BattleActor = _combat_ctrl.spawn_enemy_unit("boss_mist_wolf_king", Vector2(2025.0, 545.0), "enc_boss_wolf_king")
		if boss != null:
			var bu: Dictionary = _combat_ctrl.unit_states[boss.actor_id] as Dictionary
			bu["aggro_radius_px"] = 235.0
			_add_interactable("wolf_altar_trigger", "boss_intro", Vector2(1875.0, 505.0), 150.0, "踏上苍木灵枢祭坛迎战【雾隐狼王】 [F]", "")

	_add_zone_portal(Rect2(35.0, 1005.0, 130.0, 170.0), "qinglan_pass", "from_cave", "◀── 拾级返回青岚破庙")


## ==================== 物理帧循环、Y-Sort 55% 遮挡半透与纯键鼠交互 ====================
func _is_alt_highlight_active() -> bool:
	if InputRouter.current_mode != InputRouter.MODE_WORLD_COMBAT or _combat_ctrl.in_combat:
		return false
	return InputRouter.alt_held or _alt_key_down


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_alt_key_down = false
		if _alt_nameplate_overlay != null:
			_alt_nameplate_overlay.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var kev: InputEventKey = event as InputEventKey
		var kcode: Key = kev.physical_keycode if kev.physical_keycode != KEY_NONE else kev.keycode
		if kcode == KEY_ALT:
			_alt_key_down = kev.pressed and (InputRouter.current_mode == InputRouter.MODE_WORLD_COMBAT)
			_update_interact_prompt_and_cursor()
			if _alt_nameplate_overlay != null:
				_alt_nameplate_overlay.queue_redraw()


func _physics_process(delta: float) -> void:
	if InputRouter.current_mode == InputRouter.MODE_WORLD_COMBAT:
		_combat_ctrl.step_world_and_combat(delta, ZONE_BOUNDS)
		for npc_step: BattleActor in _npc_actors:
			if is_instance_valid(npc_step):
				npc_step.step_visuals(delta, delta, false)
		_check_dynamic_zone_triggers()
		_check_portal_overlap()
		_update_interact_prompt_and_cursor()
		_step_ambient_world_barks(delta)
	else:
		_alt_key_down = false
		_clear_all_hover_outlines()
	if _alt_nameplate_overlay != null:
		_alt_nameplate_overlay.queue_redraw()

	# 镜头平滑跟随当前主控角色，远景 0.25x 视差偏移 + Layer 3 前景竹叶视差与动态光源呼吸
	var ctrl_pos: Vector2 = _combat_ctrl.get_controlled_actor_pos()
	if not _combat_ctrl.tactical_paused:
		_camera.position = ctrl_pos
	_parallax_bg.position = -_camera.get_screen_center_position() * 0.08 - Vector2(60.0, 40.0)
	_step_m4_lighting_and_foreground(delta)
	for pm: Node2D in _portal_markers:
		if is_instance_valid(pm):
			pm.queue_redraw()

	# Layer 2 屋檐与古树树冠 55% 遮挡半透平滑过渡 + 角色淡青墨剪影（20-art-bible.md 第 5.3 节）
	_update_ysort_occlusion_fade(delta)

	# 雨丝飘落动效（支持减弱动态效果开关）
	if CampaignState.current_zone_id != "cangmu_cave" and not SaveManager.reduced_motion:
		for i: int in range(_rain_streaks.size()):
			var rp: Vector2 = _rain_streaks[i] + Vector2(-210.0, 560.0) * delta
			if rp.y > ZONE_BOUNDS.size.y:
				rp.y = 0.0
				rp.x = randf_range(0.0, ZONE_BOUNDS.size.x)
			if rp.x < 0.0:
				rp.x = ZONE_BOUNDS.size.x
			_rain_streaks[i] = rp
		_rain_overlay.queue_redraw()


func _update_ysort_occlusion_fade(delta: float) -> void:
	var living_actors: Array[BattleActor] = []
	for cid_var: Variant in _combat_ctrl.party_actors.keys():
		var pa: BattleActor = _combat_ctrl.party_actors[str(cid_var)] as BattleActor
		if pa != null and is_instance_valid(pa):
			if pa.alive:
				living_actors.append(pa)
			else:
				pa.set_occlusion_state(false, delta)
	if _combat_ctrl.pet_actor != null and is_instance_valid(_combat_ctrl.pet_actor):
		if _combat_ctrl.pet_actor.alive:
			living_actors.append(_combat_ctrl.pet_actor)
		else:
			_combat_ctrl.pet_actor.set_occlusion_state(false, delta)

	for occ: Dictionary in _occluder_sprites:
		var sp: Sprite2D = occ["sprite"] as Sprite2D
		if not is_instance_valid(sp):
			continue
		var canopy_rect: Rect2 = occ["rect"] as Rect2
		var occluded: bool = false
		for act: BattleActor in living_actors:
			var ppos: Vector2 = act.position
			if ppos.y < sp.position.y - 6.0 and canopy_rect.has_point(ppos + Vector2(0.0, -65.0)):
				occluded = true
				break
		var target_a: float = 0.55 if occluded else 1.0
		sp.modulate.a = move_toward(sp.modulate.a, target_a, delta * 3.5)

	for act_occ: BattleActor in living_actors:
		var actor_occluded: bool = false
		for occ2: Dictionary in _occluder_sprites:
			var sp2: Sprite2D = occ2["sprite"] as Sprite2D
			if not is_instance_valid(sp2):
				continue
			var crect2: Rect2 = occ2["rect"] as Rect2
			if act_occ.position.y < sp2.position.y - 6.0 and crect2.has_point(act_occ.position + Vector2(0.0, -65.0)):
				actor_occluded = true
				break
		act_occ.set_occlusion_state(actor_occluded, delta)


func _unhandled_input(event: InputEvent) -> void:
	if InputRouter.current_mode != InputRouter.MODE_WORLD_COMBAT:
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		var world_pt: Vector2 = get_canvas_transform().affine_inverse() * mb.position

		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_lmb_down = true
				_lmb_start_screen = mb.position
				_is_dragging_box = false
			else:
				_lmb_down = false
				if _is_dragging_box:
					_finish_box_selection(mb.position)
					_is_dragging_box = false
					_hud.set_box_selection_visual(false, Rect2())
				else:
					_handle_left_click_world(world_pt)

		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_handle_right_click_world(world_pt)

	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if _lmb_down and mm.position.distance_to(_lmb_start_screen) > 14.0:
			_is_dragging_box = true
			var r_pos: Vector2 = Vector2(minf(_lmb_start_screen.x, mm.position.x), minf(_lmb_start_screen.y, mm.position.y))
			var r_size: Vector2 = (mm.position - _lmb_start_screen).abs()
			_hud.set_box_selection_visual(true, Rect2(r_pos, r_size))
		var w_override: Vector2 = get_canvas_transform().affine_inverse() * mm.position
		_update_interact_prompt_and_cursor(true, w_override)


func _handle_left_click_world(world_pt: Vector2) -> void:
	# 左键仅点选目标或取消框选，绝不绑定挥剑普攻！
	_combat_ctrl.box_selected_ids.clear()
	for pa_var: Variant in _combat_ctrl.party_actors.values():
		(pa_var as BattleActor).is_box_selected = false
	if _combat_ctrl.pet_actor != null:
		_combat_ctrl.pet_actor.is_box_selected = false

	for ea: BattleActor in _combat_ctrl.enemy_actors:
		if is_instance_valid(ea) and ea.alive and ea.contains_world_point(world_pt):
			_combat_ctrl.set_locked_enemy(ea.actor_id, false)
			return

	for cid_var: Variant in _combat_ctrl.party_actors.keys():
		var cid: String = str(cid_var)
		var pa: BattleActor = _combat_ctrl.party_actors[cid] as BattleActor
		if pa.contains_world_point(world_pt):
			_combat_ctrl.switch_controlled_member(cid, false)
			return


func _interact_distance_to(pt: Vector2, ipos: Vector2) -> float:
	# 兼顾贴图底边与立面器物腹心（y-46），使角色环绕丹炉/药柜任意方位均无交互死角！
	return minf(pt.distance_to(ipos), pt.distance_to(ipos + Vector2(0.0, -46.0)))


func _is_npc_hit_point(npc: BattleActor, pt: Vector2, include_hovered: bool = true) -> bool:
	if not is_instance_valid(npc):
		return false
	if include_hovered and npc.is_hovered:
		return true
	if npc._sprite != null and npc._sprite.texture != null:
		var local_pt: Vector2 = npc._sprite.to_local(pt) - npc._sprite.offset
		var reg: Rect2 = npc._sprite.region_rect
		var rw: int = int(reg.size.x) if npc._sprite.region_enabled else npc._sprite.texture.get_width()
		var rh: int = int(reg.size.y) if npc._sprite.region_enabled else npc._sprite.texture.get_height()
		if local_pt.x >= -6.0 and local_pt.x < float(rw) + 6.0 and local_pt.y >= -6.0 and local_pt.y < float(rh) + 6.0:
			var img: Image = _get_cached_tex_image(npc._sprite.texture)
			if img != null and not img.is_empty():
				var lx: float = (float(rw) - 1.0 - local_pt.x) if npc._sprite.flip_h else local_pt.x
				var bx: int = int(floor(lx)) + (int(reg.position.x) if npc._sprite.region_enabled else 0)
				var by: int = int(floor(local_pt.y)) + (int(reg.position.y) if npc._sprite.region_enabled else 0)
				for off: Vector2i in [Vector2i(0, 0), Vector2i(-6, 0), Vector2i(6, 0), Vector2i(0, -6), Vector2i(0, 6)]:
					var sx: int = clampi(bx + off.x, 0, img.get_width() - 1)
					var sy: int = clampi(by + off.y, 0, img.get_height() - 1)
					if img.get_pixel(sx, sy).a > 0.08:
						return true
				return pt.distance_to(npc.position + Vector2(0.0, -32.0)) <= 30.0
	return npc.contains_world_point(pt)


func _get_cached_tex_image(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var key: String = tex.resource_path if tex.resource_path != "" else str(tex.get_instance_id())
	if _tex_hit_images.has(key):
		return _tex_hit_images[key] as Image
	var img: Image = tex.get_image()
	if img != null and not img.is_empty() and img.is_compressed():
		img.decompress()
	_tex_hit_images[key] = img
	return img


func _is_interactable_hit_point(inter: Dictionary, pt: Vector2, include_hovered: bool = true) -> bool:
	if float(inter.get("radius", 0.0)) <= 0.0:
		return false
	if include_hovered and _hovered_interactable_id != "" and str(inter.get("id", "")) == _hovered_interactable_id:
		return true
	var ipos: Vector2 = inter.get("pos", Vector2.ZERO) as Vector2
	var d_i: float = _interact_distance_to(pt, ipos)
	var raw_sp: Variant = inter.get("sprite", null)
	var sp: Sprite2D = (raw_sp as Sprite2D) if (raw_sp != null and is_instance_valid(raw_sp)) else null
	if sp != null and sp.texture != null:
		var local_pt: Vector2 = sp.to_local(pt) - sp.offset
		var w_px: int = sp.texture.get_width()
		var h_px: int = sp.texture.get_height()
		if local_pt.x >= -6.0 and local_pt.x < float(w_px) + 6.0 and local_pt.y >= -6.0 and local_pt.y < float(h_px) + 6.0:
			var img: Image = _get_cached_tex_image(sp.texture)
			if img != null and not img.is_empty():
				var bx: int = int(floor(local_pt.x))
				var by: int = int(floor(local_pt.y))
				for off: Vector2i in [Vector2i(0, 0), Vector2i(-6, 0), Vector2i(6, 0), Vector2i(0, -6), Vector2i(0, 6)]:
					var sx: int = clampi(bx + off.x, 0, img.get_width() - 1)
					var sy: int = clampi(by + off.y, 0, img.get_height() - 1)
					if img.get_pixel(sx, sy).a > 0.08:
						return true
				return d_i <= 46.0
			var cx: float = float(w_px) * 0.5
			var cy: float = float(h_px) * 0.52
			var d_diamond: float = absf(local_pt.x - cx) / maxf(1.0, float(w_px) * 0.44) + absf(local_pt.y - cy) / maxf(1.0, float(h_px) * 0.46)
			return d_diamond <= 1.04
		return d_i <= 46.0
	return d_i <= 78.0


func _handle_right_click_world(world_pt: Vector2) -> void:
	# 1. 右键敌人：锁定并开启自动平砍（若较远则趋近，绝不误生地面青玉水波）！
	for ea: BattleActor in _combat_ctrl.enemy_actors:
		if is_instance_valid(ea) and ea.alive and (ea.contains_world_point(world_pt) or ea.is_hovered):
			_combat_ctrl.set_locked_enemy(ea.actor_id, true)
			if not _combat_ctrl.in_combat:
				var eu: Dictionary = _combat_ctrl.unit_states.get(ea.actor_id, {}) as Dictionary
				if ea.position.distance_to(_combat_ctrl.get_controlled_actor_pos()) <= 420.0:
					_combat_ctrl.engage_enemy_group(str(eu.get("group_id", "")), _combat_ctrl.get_controlled_char_id(), true)
				else:
					_combat_ctrl.command_move_selected_to(ea.position)
			return

	# 2. 右键 NPC 或交互器物：近处直接交谈/开启，远处趋近且绝不误生地面青玉水波！
	if not _combat_ctrl.in_combat:
		for npc: BattleActor in _npc_actors:
			if is_instance_valid(npc) and _is_npc_hit_point(npc, world_pt):
				if npc.position.distance_to(_combat_ctrl.get_controlled_actor_pos()) <= 240.0:
					_trigger_npc_dialogue(npc.actor_id)
				else:
					_combat_ctrl.command_move_selected_to(npc.position)
				return
		for inter: Dictionary in _interactables:
			if _is_interactable_hit_point(inter, world_pt):
				var ipos: Vector2 = inter.get("pos", Vector2.ZERO) as Vector2
				if _interact_distance_to(_combat_ctrl.get_controlled_actor_pos(), ipos) <= maxf(220.0, float(inter.get("radius", 120.0))):
					_activate_interactable(inter)
				else:
					_combat_ctrl.command_move_selected_to(ipos)
				return

	# 3. 右键地面：指挥选中队员或当前主控角色移动走位，并绽放青玉水波落点（敌/NPC/器物已提前返回，绝不误生水波）！
	_combat_ctrl.command_move_selected_to(world_pt)
	if _ground_vfx != null:
		_ground_vfx.spawn_move_ripple(world_pt)


func _finish_box_selection(end_screen: Vector2) -> void:
	var r_pos: Vector2 = Vector2(minf(_lmb_start_screen.x, end_screen.x), minf(_lmb_start_screen.y, end_screen.y))
	var r_size: Vector2 = (end_screen - _lmb_start_screen).abs()
	var srect: Rect2 = Rect2(r_pos, r_size)
	_combat_ctrl.box_selected_ids.clear()

	var vp_half: Vector2 = get_viewport_rect().size * 0.5
	var cam_c: Vector2 = _camera.get_screen_center_position()

	for cid_var: Variant in _combat_ctrl.party_actors.keys():
		var cid: String = str(cid_var)
		var pa: BattleActor = _combat_ctrl.party_actors[cid] as BattleActor
		var scr_pt: Vector2 = (pa.position - Vector2(0.0, 55.0) - cam_c) * _camera.zoom + vp_half
		var hit: bool = pa.alive and srect.has_point(scr_pt)
		pa.is_box_selected = hit
		if hit:
			_combat_ctrl.box_selected_ids.append(cid)

	if _combat_ctrl.pet_actor != null and _combat_ctrl.pet_actor.alive:
		var p_scr: Vector2 = (_combat_ctrl.pet_actor.position - Vector2(0.0, 35.0) - cam_c) * _camera.zoom + vp_half
		var phit: bool = srect.has_point(p_scr)
		_combat_ctrl.pet_actor.is_box_selected = phit
		if phit:
			_combat_ctrl.box_selected_ids.append(_combat_ctrl.pet_actor.actor_id)


func _clear_all_hover_outlines() -> void:
	_hovered_interactable_id = ""
	if _combat_ctrl != null:
		_combat_ctrl.hovered_world_actor_id = ""
		for ea_c: BattleActor in _combat_ctrl.enemy_actors:
			if is_instance_valid(ea_c) and ea_c.is_hovered:
				ea_c.is_hovered = false
				ea_c.queue_redraw()
		for pa_var_c: Variant in _combat_ctrl.party_actors.values():
			var pa_c: BattleActor = pa_var_c as BattleActor
			if is_instance_valid(pa_c) and pa_c.is_hovered:
				pa_c.is_hovered = false
				pa_c.queue_redraw()
	for inter_c: Dictionary in _interactables:
		var raw_sp_c: Variant = inter_c.get("sprite", null)
		if raw_sp_c != null and is_instance_valid(raw_sp_c):
			var sp_c: Sprite2D = raw_sp_c as Sprite2D
			if sp_c != null and sp_c.material is ShaderMaterial:
				(sp_c.material as ShaderMaterial).set_shader_parameter("outline_intensity", 0.0)
	for npc_c: BattleActor in _npc_actors:
		if is_instance_valid(npc_c):
			if npc_c.is_hovered:
				npc_c.is_hovered = false
				npc_c.queue_redraw()
			if npc_c._overlay_canvas != null and is_instance_valid(npc_c._overlay_canvas):
				npc_c._overlay_canvas.queue_redraw()
			if npc_c._sprite != null and is_instance_valid(npc_c._sprite) and npc_c._sprite.material is ShaderMaterial:
				(npc_c._sprite.material as ShaderMaterial).set_shader_parameter("outline_intensity", 0.0)
	if _hud != null:
		_hud.set_interact_prompt("")
	_set_cursor_mode(0)


func _update_interact_prompt_and_cursor(has_world_override: bool = false, world_override: Vector2 = Vector2.ZERO) -> void:
	var wmouse: Vector2 = world_override if has_world_override else get_global_mouse_position()
	_combat_ctrl.hovered_world_actor_id = ""
	var over_enemy: bool = false
	var over_interact: bool = false
	var alt_active: bool = _is_alt_highlight_active()

	for ea: BattleActor in _combat_ctrl.enemy_actors:
		if is_instance_valid(ea):
			var next_ehov: bool = ea.alive and ea.contains_world_point(wmouse)
			if ea.is_hovered != next_ehov:
				ea.is_hovered = next_ehov
				ea.queue_redraw()
			if ea.is_hovered:
				over_enemy = true

	for cid_var: Variant in _combat_ctrl.party_actors.keys():
		var cid: String = str(cid_var)
		var raw_pa: Variant = _combat_ctrl.party_actors[cid]
		if raw_pa != null and is_instance_valid(raw_pa):
			var pa: BattleActor = raw_pa as BattleActor
			var next_phov: bool = pa.alive and pa.contains_world_point(wmouse)
			if pa.is_hovered != next_phov:
				pa.is_hovered = next_phov
				pa.queue_redraw()
			if pa.is_hovered:
				_combat_ctrl.hovered_world_actor_id = cid

	for npc: BattleActor in _npc_actors:
		if is_instance_valid(npc):
			var next_nhov: bool = (not _combat_ctrl.in_combat) and _is_npc_hit_point(npc, wmouse, false)
			if npc.is_hovered != next_nhov:
				npc.is_hovered = next_nhov
				npc.queue_redraw()
				if npc._overlay_canvas != null and is_instance_valid(npc._overlay_canvas):
					npc._overlay_canvas.queue_redraw()
			if npc.is_hovered:
				over_interact = true
			if npc._sprite != null and is_instance_valid(npc._sprite) and npc._sprite.material is ShaderMaterial:
				var npc_sm: ShaderMaterial = npc._sprite.material as ShaderMaterial
				npc_sm.set_shader_parameter("outline_intensity", 1.0 if npc.is_hovered else (0.38 if alt_active else 0.0))

	# 器物悬停精细碰撞与描边强度更新（离开悬停且未按 Alt 时立即归零至 0.0）
	var best_hover_inter_idx: int = -1
	var best_hover_dist: float = 99999.0
	if not _combat_ctrl.in_combat:
		for idx_i: int in range(_interactables.size()):
			var inter_h: Dictionary = _interactables[idx_i]
			if not _is_interactable_hit_point(inter_h, wmouse, false):
				continue
			var ipos_h: Vector2 = inter_h.get("pos", Vector2.ZERO) as Vector2
			var d_h: float = _interact_distance_to(wmouse, ipos_h)
			if d_h < best_hover_dist:
				best_hover_dist = d_h
				best_hover_inter_idx = idx_i

	_hovered_interactable_id = ""
	if best_hover_inter_idx >= 0:
		over_interact = true
		_hovered_interactable_id = str(_interactables[best_hover_inter_idx].get("id", ""))

	for idx_u: int in range(_interactables.size()):
		var inter_u: Dictionary = _interactables[idx_u]
		var raw_sp_u: Variant = inter_u.get("sprite", null)
		if raw_sp_u != null and is_instance_valid(raw_sp_u):
			var sp_u: Sprite2D = raw_sp_u as Sprite2D
			if sp_u != null and sp_u.material is ShaderMaterial:
				var sm_u: ShaderMaterial = sp_u.material as ShaderMaterial
				var is_hov: bool = (idx_u == best_hover_inter_idx)
				var valid_u: bool = (float(inter_u.get("radius", 0.0)) > 0.0)
				var out_str: float = 1.0 if is_hov else (0.38 if (alt_active and valid_u) else 0.0)
				sm_u.set_shader_parameter("outline_intensity", out_str)

	var ctrl_pos: Vector2 = _combat_ctrl.get_controlled_actor_pos()
	var best_prompt: String = ""
	var best_d: float = 175.0
	var best_world_anchor: Vector2 = Vector2(-1.0, -1.0)
	var best_target_pos: Vector2 = Vector2(-1.0, -1.0)

	if not _combat_ctrl.in_combat:
		for npc2: BattleActor in _npc_actors:
			if is_instance_valid(npc2):
				var dn: float = ctrl_pos.distance_to(npc2.position)
				if dn < best_d:
					best_d = dn
					best_prompt = "[F / 右键] 与 %s 交谈" % npc2.display_name
					best_target_pos = npc2.position
					best_world_anchor = npc2.position + Vector2(0.0, -168.0)

		for inter: Dictionary in _interactables:
			var ipos: Vector2 = inter.get("pos", Vector2.ZERO) as Vector2
			var rad: float = float(inter.get("radius", 120.0))
			var di: float = _interact_distance_to(ctrl_pos, ipos)
			if di <= rad and di < best_d + 25.0:
				best_d = di
				best_prompt = str(inter.get("title", "[F] 交互"))
				best_target_pos = ipos
				var anchor_y: float = minf(ipos.y - 148.0, ctrl_pos.y - 182.0)
				best_world_anchor = Vector2(ipos.x, anchor_y)

	var place_below: bool = false
	if best_prompt != "" and best_target_pos.x >= 0.0:
		if _has_nearby_active_bark(best_target_pos) or _has_nearby_active_bark(ctrl_pos):
			place_below = true
			best_world_anchor = Vector2(best_target_pos.x, maxf(best_target_pos.y, ctrl_pos.y) + 14.0)

	var scr_anchor: Vector2 = Vector2(-1.0, -1.0)
	if best_prompt != "" and best_world_anchor.x >= 0.0:
		var vp_half: Vector2 = get_viewport_rect().size * 0.5
		var cam_c: Vector2 = _camera.get_screen_center_position()
		scr_anchor = (best_world_anchor - cam_c) * _camera.zoom + vp_half
	_hud.set_interact_prompt(best_prompt, scr_anchor, place_below)
	if over_enemy:
		_set_cursor_mode(1)
	elif over_interact:
		_set_cursor_mode(2)
	else:
		_set_cursor_mode(0)


func _has_nearby_active_bark(ref_pos: Vector2) -> bool:
	for pa_var: Variant in _combat_ctrl.party_actors.values():
		var pa: BattleActor = pa_var as BattleActor
		if is_instance_valid(pa) and pa.has_active_bark() and pa.position.distance_to(ref_pos) <= 320.0:
			return true
	for npc: BattleActor in _npc_actors:
		if is_instance_valid(npc) and npc.has_active_bark() and npc.position.distance_to(ref_pos) <= 320.0:
			return true
	return false


func _clear_all_world_barks() -> void:
	for pa_var: Variant in _combat_ctrl.party_actors.values():
		var pa: BattleActor = pa_var as BattleActor
		if is_instance_valid(pa):
			pa.clear_world_bark()
	for npc: BattleActor in _npc_actors:
		if is_instance_valid(npc):
			npc.clear_world_bark()


func _try_interact_nearest() -> void:
	if _combat_ctrl.in_combat:
		return
	var ctrl_pos: Vector2 = _combat_ctrl.get_controlled_actor_pos()

	var best_npc: BattleActor = null
	var best_nd: float = 175.0
	for npc: BattleActor in _npc_actors:
		if is_instance_valid(npc):
			var dn: float = ctrl_pos.distance_to(npc.position)
			if dn <= best_nd:
				best_nd = dn
				best_npc = npc

	var best_inter: Dictionary = {}
	var best_idist: float = 9999.0
	for inter: Dictionary in _interactables:
		var ipos: Vector2 = inter.get("pos", Vector2.ZERO) as Vector2
		var di: float = _interact_distance_to(ctrl_pos, ipos)
		if di <= float(inter.get("radius", 120.0)) and di < best_idist:
			best_idist = di
			best_inter = inter

	if not best_inter.is_empty() and (best_npc == null or best_idist <= best_nd + 18.0):
		_activate_interactable(best_inter)
		return
	if best_npc != null:
		_trigger_npc_dialogue(best_npc.actor_id)


func _trigger_npc_dialogue(npc_id: String) -> void:
	match npc_id:
		"npc_elder":
			if str(CampaignState.world_flags.get("marrow_choice", "")) == "scatter":
				_clear_all_world_barks()
				for n: BattleActor in _npc_actors:
					if n.actor_id == "npc_elder":
						n.show_world_bark("多亏灵雨天降，全镇染瘴乡亲都除根痊愈啦！恩公大德！", 4.5)
			else:
				_narrative.start_dialogue("dlg_ch01_tea_gossip")
		"npc_peddler":
			if not CampaignState.read_dialogues.has("dlg_ch01_peddler_resonance"):
				_narrative.start_dialogue("dlg_ch01_peddler_resonance")
			else:
				_modals.open_shop_modal("shop_tingyu_peddler")
		"shen_npc":
			_narrative.start_dialogue("dlg_ch01_meet_shen")
		"npc_zhou":
			if CampaignState.get_item_count("item_yaolu_jade_token") > 0 or CampaignState.unlocked_clues.has("clue_yaolu_spy_token"):
				_narrative.start_dialogue("dlg_ch01_confront_zhou")
			else:
				_clear_all_world_barks()
				for nz: BattleActor in _npc_actors:
					if nz.actor_id == "npc_zhou":
						nz.show_world_bark("咳……药庐灵草紧缺，闲杂散修莫在库房附近乱转。", 3.8)


func _activate_interactable(inter: Dictionary) -> void:
	var kind: String = str(inter.get("kind", ""))
	var iid: String = str(inter.get("id", ""))

	match kind:
		"stele":
			var sp: Sprite2D = inter.get("sprite", null) as Sprite2D
			if sp != null and ResourceLoader.exists("res://assets/world/prop_stele_lit.png"):
				sp.texture = load("res://assets/world/prop_stele_lit.png") as Texture2D
			_modals.open_stele_modal(iid, str(inter.get("title", "引灵石碑")))
		"alchemy":
			_modals.open_alchemy_furnace()
		"shop":
			_modals.open_shop_modal("shop_yaolu_pharmacy")
		"stall":
			if not CampaignState.read_dialogues.has("dlg_ch01_peddler_resonance"):
				_narrative.start_dialogue("dlg_ch01_peddler_resonance")
			else:
				_modals.open_shop_modal("shop_tingyu_peddler")
		"burnt_pill_pickup":
			if not CampaignState.opened_containers.has(iid):
				CampaignState.opened_containers[iid] = true
				CampaignState.add_item("item_burnt_pill", 1, false)
				NotifyHub.push_explore_slip("翻得弃置废丹", "拾获药童弃置的【焦黑废丹】×1，可按 B 置入断玉剑匣试炼提纯！", "loot")
				_remove_interactable_visual(inter)
		"herb":
			if not CampaignState.opened_containers.has(iid):
				CampaignState.opened_containers[iid] = true
				CampaignState.add_item("item_qingmu_leaf", 2, false)
				CampaignState.add_item("item_ningqi_herb", 2, false)
				_remove_interactable_visual(inter)
		"herb_fire":
			if not CampaignState.opened_containers.has(iid):
				CampaignState.opened_containers[iid] = true
				CampaignState.add_item("item_chiyang_fungus", 2, false)
				_remove_interactable_visual(inter)
		"herb_corrupt":
			if not CampaignState.opened_containers.has(iid):
				CampaignState.opened_containers[iid] = true
				CampaignState.add_item("item_corrupt_flower", 2, false)
				_remove_interactable_visual(inter)
		"chest_poxue":
			if not CampaignState.opened_containers.has(iid):
				CampaignState.opened_containers[iid] = true
				CampaignState.add_item("eq_pendant_poxue", 1, false)
				CampaignState.add_spirit_stones(65, false)
				_audio.play_sfx("sfx_alchemy_success", AudioDirector.TIER_A, true)
				_remove_interactable_visual(inter)
		"cliff_vista":
			CampaignState.unlock_clue("clue_golden_core_cliff")
			_clear_all_world_barks()
			var ctrl_a: BattleActor = _combat_ctrl.get_controlled_actor()
			if ctrl_a != null:
				ctrl_a.show_world_bark("断崖绝壁相隔百丈，待日后结成金丹御剑飞行再来取此秘匣。", 4.2)
		"beast_rescue":
			CampaignState.quest_states["q_side_spirit_pet"] = "stage_rescue_beast"
			_narrative.start_dialogue("dlg_ch01_rescue_beast")
		"temple_clash":
			_narrative.start_dialogue("dlg_ch01_temple_clash")
		"fire_barrier":
			# 五行破禁 ①：火焚毒棘墙
			CampaignState.world_flags["vine_wall_burned"] = true
			_clear_all_world_barks()
			_audio.play_element_sfx("fire", AudioDirector.TIER_A)
			_sky_vfx.spawn_ring_burst(inter.get("pos", Vector2.ZERO) as Vector2, 160.0, UIThemeBuilder.COL_CINNABAR_RED, 0.55)
			NotifyHub.push_explore_slip("五行破禁 · 真火焚棘", "引赤阳剑火焚尽阻路腐瘴毒棘！", "unlock")
			_clear_obstacle_and_remove(inter)
		"water_barrier":
			if not bool(CampaignState.world_flags.get("miasma_pool_cleansed", false)):
				CampaignState.world_flags["miasma_pool_cleansed"] = true
				_audio.play_element_sfx("water", AudioDirector.TIER_A)
				var sp_p: Sprite2D = inter.get("sprite", null) as Sprite2D
				if sp_p != null and ResourceLoader.exists("res://assets/world/prop_miasma_pool_clean.png"):
					sp_p.texture = load("res://assets/world/prop_miasma_pool_clean.png") as Texture2D
				inter["title"] = "清冽灵泉池（已由沈清禾玄水净化）"
				CampaignState.add_item("item_marrow_dew", 1, false)
				NotifyHub.push_explore_slip("五行破禁 · 玄水净池", "死水化作清泉，池畔古修遗刻显露真容！", "unlock")
		"remains":
			if not bool(CampaignState.world_flags.get("miasma_pool_cleansed", false)):
				_clear_all_world_barks()
				var ctrl_b: BattleActor = _combat_ctrl.get_controlled_actor()
				if ctrl_b != null:
					ctrl_b.show_world_bark("池中腐瘴扑面，须先按 F 净化前方瘴毒潭方可靠近。", 3.8)
			elif not CampaignState.read_dialogues.has("dlg_ch01_ancient_remains"):
				_narrative.start_dialogue("dlg_ch01_ancient_remains")
		"shortcut_gate":
			if not bool(CampaignState.world_flags.get("shortcut_gate_opened", false)):
				if _combat_ctrl.get_controlled_actor_pos().y > 895.0:
					_clear_all_world_barks()
					var ctrl_g: BattleActor = _combat_ctrl.get_controlled_actor()
					if ctrl_g != null:
						ctrl_g.show_world_bark("此回环石门机括设在北侧内廊，须先焚毁东侧毒棘绕回开启。", 3.8)
				else:
					CampaignState.world_flags["shortcut_gate_opened"] = true
					_audio.play_sfx("sfx_stele_activate", AudioDirector.TIER_A)
					NotifyHub.push_explore_slip("奇门捷径贯通", "古窟回环石门已开启，可直通入口石阶！", "unlock")
					var obs_i: int = int(inter.get("obstacle_idx", -1))
					if obs_i >= 0 and obs_i < _combat_ctrl.obstacle_circles.size():
						_combat_ctrl.obstacle_circles[obs_i] = {"pos": Vector2(-9999.0, -9999.0), "radius": 1.0}
					inter["title"] = "回环捷径石门（已贯通）"
		"boss_intro":
			_narrative.start_dialogue("dlg_ch01_wolf_king_intro")


func _check_dynamic_zone_triggers() -> void:
	if _combat_ctrl.in_combat or _narrative.visible or _modals.visible or _casket.visible:
		return
	var ppos: Vector2 = _combat_ctrl.get_controlled_actor_pos()

	# 山道竹林“怀璧招劫”事件链：在地摊捡漏古剑魄残铁后路过竹林触发黑衣劫修二人组伏击！
	if CampaignState.current_zone_id == "qinglan_pass":
		if bool(CampaignState.world_flags.get("peddler_gem_bought", false)) and not bool(CampaignState.world_flags.get("rogue_ambush_cleared", false)):
			if not CampaignState.read_dialogues.has("dlg_ch01_rogue_ambush") and ppos.distance_to(Vector2(1120.0, 820.0)) <= 220.0:
				_narrative.start_dialogue("dlg_ch01_rogue_ambush")

		# 走近破庙大门自动触发破庙初阵与全屏动态 CG
		if not bool(CampaignState.world_flags.get("met_pei_zhao", false)) and ppos.distance_to(Vector2(1890.0, 640.0)) <= 155.0:
			_narrative.start_dialogue("dlg_ch01_temple_clash")

	elif CampaignState.current_zone_id == "cangmu_cave":
		if not bool(CampaignState.world_flags.get("wolf_king_defeated", false)) and ppos.distance_to(Vector2(1875.0, 505.0)) <= 145.0:
			if not CampaignState.read_dialogues.has("dlg_ch01_wolf_king_intro"):
				_narrative.start_dialogue("dlg_ch01_wolf_king_intro")


func _check_portal_overlap() -> void:
	if _combat_ctrl.in_combat:
		return
	var ppos: Vector2 = _combat_ctrl.get_controlled_actor_pos()
	for portal: Dictionary in _zone_portals:
		var prect: Rect2 = portal["rect"] as Rect2
		if prect.has_point(ppos):
			var tzone: String = str(portal["target_zone"])
			var tspawn: String = str(portal["target_spawn"])
			SaveManager.save_rolling_auto()
			load_zone(tzone, tspawn, false)
			return


func _execute_dialogue_action(act: Dictionary) -> void:
	var atype: String = str(act.get("type", ""))
	match atype:
		"set_flag":
			CampaignState.world_flags[str(act.get("key", ""))] = act.get("value", true)
		"recruit":
			var cid: String = str(act.get("char_id", ""))
			var slot_n: int = int(act.get("slot", 2))
			CampaignState.recruit_companion(cid, slot_n)
			_combat_ctrl.sync_party_roster_in_place()
			if cid == "shen_qinghe":
				_remove_npc_by_id("shen_npc")
		"unlock_formation":
			CampaignState.unlock_formation(str(act.get("id", "dizai")), bool(act.get("auto_equip", false)))
			_combat_ctrl.sync_party_roster_in_place()
		"advance_realm":
			CampaignState.advance_member_realm(str(act.get("char_id", "gu_changqing")), str(act.get("realm_id", "qi_refining_1")), str(act.get("grade", "flawless")))
			_combat_ctrl.sync_party_roster_in_place()
		"contract_pet":
			CampaignState.contract_spirit_pet(str(act.get("pet_id", "pet_fire_fox")))
			_combat_ctrl.sync_pet_actor(_combat_ctrl.get_controlled_actor_pos() + Vector2(42.0, 32.0))
			_remove_interactable_by_id("injured_beast")
		"set_quest_stage":
			CampaignState.quest_states[str(act.get("quest_id", ""))] = str(act.get("stage", ""))
			CampaignState.journal_updated.emit()
		"unlock_clue":
			CampaignState.unlock_clue(str(act.get("id", "")))
		"add_stones":
			CampaignState.add_spirit_stones(int(act.get("amount", 0)), false)
		"add_item":
			CampaignState.add_item(str(act.get("id", "")), int(act.get("count", 1)), false)
		"add_rep":
			CampaignState.add_faction_reputation(str(act.get("faction_id", "")), int(act.get("amount", 0)))
		"add_bond":
			CampaignState.add_companion_bond(str(act.get("char_id", "")), int(act.get("amount", 1)))
		"mark_night_talk":
			var ntid: String = str(act.get("id", ""))
			if not CampaignState.viewed_night_talks.has(ntid):
				CampaignState.viewed_night_talks.append(ntid)
		"stamp_seal":
			CampaignState.stamp_ink_seal(str(act.get("seal_id", "")), str(act.get("axis", "")))
		"spawn_temple_pack":
			_remove_interactable_by_id("temple_event_trigger")
			var ppos: Vector2 = _combat_ctrl.get_controlled_actor_pos()
			var w1: BattleActor = _combat_ctrl.spawn_enemy_unit("rot_wolf", ppos + Vector2(165.0, -35.0), "enc_temple_wolves")
			var w2: BattleActor = _combat_ctrl.spawn_enemy_unit("rot_wolf", ppos + Vector2(185.0, 45.0), "enc_temple_wolves")
			var sh: BattleActor = _combat_ctrl.spawn_enemy_unit("miasma_shaman", ppos + Vector2(245.0, 5.0), "enc_temple_wolves")
			if w1 != null or w2 != null or sh != null:
				_combat_ctrl.engage_enemy_group("enc_temple_wolves", "pei_zhao", false)
		"spawn_rogue_ambush":
			var rpos: Vector2 = _combat_ctrl.get_controlled_actor_pos()
			_combat_ctrl.spawn_enemy_unit("rogue_cultivator", rpos + Vector2(150.0, -30.0), "enc_rogue_ambush")
			_combat_ctrl.spawn_enemy_unit("rogue_cultivator", rpos + Vector2(160.0, 50.0), "enc_rogue_ambush")
			_combat_ctrl.engage_enemy_group("enc_rogue_ambush", "gu_changqing", false)
		"engage_boss_wolf_king":
			_remove_interactable_by_id("wolf_altar_trigger")
			_combat_ctrl.engage_enemy_group("enc_boss_wolf_king", _combat_ctrl.get_controlled_char_id(), false)
		"show_chapter_complete_scroll":
			SaveManager.save_rolling_auto()
			_modals.open_chapter_complete_modal()


func _on_dialogue_finished(dialogue_id: String) -> void:
	if dialogue_id.begins_with("dlg_night_talk_"):
		_audio.stop_special_bgm_return_to_field()
	elif dialogue_id == "dlg_ch01_peddler_resonance":
		_modals.open_shop_modal("shop_tingyu_peddler")
	elif dialogue_id == "dlg_ch01_confront_zhou":
		_remove_npc_by_id("npc_zhou")


func _on_encounter_cleared(group_id: String, _was_boss: bool) -> void:
	var epoch: int = CampaignState.scene_epoch
	if group_id == "enc_temple_wolves":
		# 0.8s 战意收束静默收剑后再进立绘对话（14-narrative-design.md 第 8 节铁律！）
		get_tree().create_timer(0.80).timeout.connect(func() -> void:
			if CampaignState.scene_epoch != epoch:
				return
			_add_zone_portal(Rect2(2060.0, 565.0, 150.0, 130.0), "cangmu_cave", "from_pass", "破庙地脉石阶 ──▶ 苍木灵枢古窟")
			_narrative.start_dialogue("dlg_ch01_temple_aftermath")
		)
	elif group_id == "enc_rogue_ambush":
		CampaignState.world_flags["rogue_ambush_cleared"] = true
		CampaignState.add_item("item_bloodied_pouch", 1, false)
		CampaignState.quest_states["q_side_yaolu_spy"] = "stage_confront_zhou"
		NotifyHub.push_explore_slip("反杀夺宝成功", "搜出【染血储物袋】，可按 B 在行囊中开启查验！", "loot")
	elif group_id == "enc_boss_wolf_king":
		CampaignState.world_flags["wolf_king_defeated"] = true
		CampaignState.quest_states["q_main_ch01"] = "stage_marrow_choice"
		get_tree().create_timer(0.85).timeout.connect(func() -> void:
			if CampaignState.scene_epoch != epoch:
				return
			_narrative.start_dialogue("dlg_ch01_marrow_choice")
		)


func _respawn_at_latest_stele() -> void:
	var sid: String = CampaignState.last_rested_stele_id
	CampaignState.rest_at_stele(sid)
	var target_z: String = "tingyu_town"
	if sid == "stele_temple_courtyard":
		target_z = "qinglan_pass"
	elif sid.begins_with("stele_cave") or sid.begins_with("stele_wolf"):
		target_z = "cangmu_cave"
	load_zone(target_z, sid, false)


## ==================== 场景拼装底层辅助 ====================
func _add_tiled_ground(tex_path: String, rect: Rect2) -> void:
	var bleed_rect: Rect2 = rect.grow(320.0)
	var poly: Polygon2D = Polygon2D.new()
	poly.polygon = PackedVector2Array([
		bleed_rect.position,
		Vector2(bleed_rect.end.x, bleed_rect.position.y),
		bleed_rect.end,
		Vector2(bleed_rect.position.x, bleed_rect.end.y),
	])
	if ResourceLoader.exists(tex_path):
		poly.texture = load(tex_path) as Texture2D
		poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	else:
		poly.color = Color("#343E3A")
	_ground_base_sub.add_child(poly)


func _add_road_polygon(pts: PackedVector2Array, tex_path: String) -> void:
	var poly_idx: int = _mm_roads.size()
	_mm_roads.append(pts)

	# 0. 路肩湿泥青苔柔化晕边（绘于 _road_feather_sub 底层，使青石路缘自然嵌入泥土草坡零刀切感！）
	var feather: Node2D = Node2D.new()
	feather.draw.connect(func() -> void:
		var n_pts: int = pts.size()
		for fi: int in range(n_pts):
			var fa: Vector2 = pts[fi]
			var fb: Vector2 = pts[(fi + 1) % n_pts]
			var flen: float = fa.distance_to(fb)
			if flen < 24.0 or (fa.x <= 65.0 and fb.x <= 65.0) or (fa.x >= 2345.0 and fb.x >= 2345.0):
				continue
			var fdir: Vector2 = (fb - fa) / flen
			var fnorm: Vector2 = Vector2(-fdir.y, fdir.x)
			if Geometry2D.is_point_in_polygon((fa + fb) * 0.5 + fnorm * 6.0, pts):
				fnorm = -fnorm
			var fsteps: int = maxi(1, int(floor(flen / 68.0)))
			for fs: int in range(fsteps):
				var ft0: float = float(fs) / float(fsteps)
				var ft1: float = float(fs + 1) / float(fsteps)
				var sa: Vector2 = fa.lerp(fb, ft0)
				var sb: Vector2 = fa.lerp(fb, ft1)
				var smid: Vector2 = (sa + sb) * 0.5
				var inside_adj: bool = false
				for o_i: int in range(_mm_roads.size()):
					if o_i != poly_idx and Geometry2D.is_point_in_polygon(smid + fnorm * 10.0, _mm_roads[o_i]):
						inside_adj = true
						break
				if not inside_adj:
					feather.draw_colored_polygon(
						PackedVector2Array([sa - fnorm * 2.0, sb - fnorm * 2.0, sb + fnorm * 15.0, sa + fnorm * 15.0]),
						Color(0.13, 0.17, 0.14, 0.28)
					)
	)
	_road_feather_sub.add_child(feather)

	# 1. 不透明青石板主体（雨中听雨镇与山道挂载受光 wet_bluestone.gdshader 呈现水膜天光与暖/冷灯火倒影！）
	var poly: Polygon2D = Polygon2D.new()
	poly.polygon = pts
	if ResourceLoader.exists(tex_path):
		poly.texture = load(tex_path) as Texture2D
		poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		poly.color = Color(0.86, 0.90, 0.87, 1.0)
	else:
		poly.color = Color("#56615E")
	if CampaignState.current_zone_id != "cangmu_cave" and _wet_bluestone_shader != null:
		var rmat: ShaderMaterial = ShaderMaterial.new()
		rmat.shader = _wet_bluestone_shader
		rmat.set_shader_parameter("wetness", 0.74)
		rmat.set_shader_parameter("ripple_speed", 0.0 if SaveManager.reduced_motion else 1.0)
		rmat.set_shader_parameter("ripple_strength", 0.34)
		poly.material = rmat
		_wet_road_materials.append(rmat)
	_road_stone_sub.add_child(poly)

	# 2. 沿通路切线排布收边石（城镇/山道用整齐青石条石，地底古窟用参差苍苔碎岩收口，彻底消除城镇砖边穿帮与锯齿！）
	var is_cave_road: bool = (CampaignState.current_zone_id == "cangmu_cave")
	var curb: Node2D = Node2D.new()
	curb.draw.connect(func() -> void:
		var count_pts: int = pts.size()
		for i: int in range(count_pts):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % count_pts]
			var seg_len: float = a.distance_to(b)
			if seg_len < 24.0:
				continue
			if (a.x <= 65.0 and b.x <= 65.0) or (a.x >= 2345.0 and b.x >= 2345.0):
				continue
			var dir_v: Vector2 = (b - a) / seg_len
			var norm_v: Vector2 = Vector2(-dir_v.y, dir_v.x)
			if Geometry2D.is_point_in_polygon((a + b) * 0.5 + norm_v * 6.0, pts):
				norm_v = -norm_v
			var step_span: float = 42.0 if is_cave_road else 34.0
			var steps: int = maxi(2, int(floor(seg_len / step_span)))
			var half_len: float = (seg_len / float(steps)) * (0.42 if is_cave_road else 0.46)
			var half_thk: float = 6.2 if is_cave_road else 4.5
			for s_i: int in range(steps):
				var t: float = (float(s_i) + 0.5) / float(steps)
				var base_p: Vector2 = a.lerp(b, t)
				var inside_other: bool = false
				for o_idx: int in range(_mm_roads.size()):
					if o_idx == poly_idx:
						continue
					var o_poly: PackedVector2Array = _mm_roads[o_idx]
					if (
						Geometry2D.is_point_in_polygon(base_p, o_poly)
						or Geometry2D.is_point_in_polygon(base_p + norm_v * 9.0, o_poly)
						or Geometry2D.is_point_in_polygon(base_p - norm_v * 9.0, o_poly)
					):
						inside_other = true
						break
				if inside_other:
					continue
				var h_seed: float = sin(float(i * 31 + s_i * 17) * 1.73)
				var h_seed2: float = cos(float(i * 19 + s_i * 29) * 2.11)
				if is_cave_road:
					var c_center: Vector2 = base_p + norm_v * (h_seed * 2.6)
					var hl_a: float = half_len * (0.82 + 0.28 * absf(h_seed))
					var ht_a: float = half_thk * (0.76 + 0.36 * absf(h_seed2))
					var cobble: PackedVector2Array = PackedVector2Array([
						c_center - dir_v * hl_a - norm_v * (ht_a * 0.65),
						c_center - dir_v * (hl_a * 0.25) - norm_v * ht_a,
						c_center + dir_v * hl_a - norm_v * (ht_a * 0.55),
						c_center + dir_v * (hl_a * 0.85) + norm_v * (ht_a * 0.80),
						c_center + dir_v * (hl_a * 0.10) + norm_v * (ht_a * 1.08),
						c_center - dir_v * (hl_a * 0.88) + norm_v * (ht_a * 0.72),
					])
					curb.draw_colored_polygon(
						cobble,
						Color(0.24 + 0.03 * h_seed, 0.29 + 0.03 * h_seed, 0.27 + 0.02 * h_seed2, 0.90)
					)
					curb.draw_polyline(
						PackedVector2Array([cobble[0], cobble[1], cobble[2], cobble[3], cobble[4], cobble[5], cobble[0]]),
						Color(0.10, 0.13, 0.12, 0.82),
						1.5
					)
				else:
					var p0: Vector2 = base_p - dir_v * half_len - norm_v * half_thk
					var p1: Vector2 = base_p + dir_v * half_len - norm_v * half_thk
					var p2: Vector2 = base_p + dir_v * half_len + norm_v * half_thk
					var p3: Vector2 = base_p - dir_v * half_len + norm_v * half_thk
					var sh_off: Vector2 = norm_v * 2.5 + Vector2(1.0, 1.8)
					curb.draw_colored_polygon(
						PackedVector2Array([p0 + sh_off, p1 + sh_off, p2 + sh_off, p3 + sh_off]),
						Color(0.11, 0.14, 0.12, 0.32)
					)
					var stone_tone: float = 0.03 * h_seed
					curb.draw_colored_polygon(
						PackedVector2Array([p0, p1, p2, p3]),
						Color(0.37 + stone_tone, 0.43 + stone_tone, 0.40 + stone_tone, 0.98)
					)
					curb.draw_polyline(
						PackedVector2Array([p0, p1, p2, p3, p0]),
						Color(0.16, 0.20, 0.18, 0.88),
						1.4
					)
	)
	_road_curb_sub.add_child(curb)


func _add_ysort_structure(tex_path: String, base_pos: Vector2, collision_r: float, can_occlude: bool) -> Sprite2D:
	var sp: Sprite2D = Sprite2D.new()
	sp.position = base_pos
	sp.centered = false
	if ResourceLoader.exists(tex_path):
		var tex: Texture2D = load(tex_path) as Texture2D
		sp.texture = tex
		var tw: float = float(tex.get_width())
		var th: float = float(tex.get_height())
		sp.offset = Vector2(-tw * 0.5, -th)
		if can_occlude:
			var occ_rect: Rect2 = Rect2(base_pos.x - tw * 0.44, base_pos.y - th * 0.94, tw * 0.88, th * 0.80)
			if tex_path.contains("alchemy_pavilion"):
				occ_rect = Rect2(base_pos.x - tw * 0.46, base_pos.y - th * 0.96, tw * 0.92, th * 0.42)
			elif tex_path.contains("bamboo_cluster"):
				occ_rect = Rect2(base_pos.x - tw * 0.36, base_pos.y - th * 0.82, tw * 0.72, th * 0.68)
			elif tex_path.contains("folk_house") or tex_path.contains("folk_roof_eave") or tex_path.contains("yaolu_hall") or tex_path.contains("tea_pavilion") or tex_path.contains("ruined_temple"):
				occ_rect = Rect2(base_pos.x - tw * 0.44, base_pos.y - th * 0.94, tw * 0.88, th * 0.66)
			_occluder_sprites.append({
				"sprite": sp,
				"rect": occ_rect,
			})
		var is_arch_bldg: bool = (
			tex_path.contains("folk_house")
			or tex_path.contains("folk_roof_eave")
			or tex_path.contains("tea_pavilion")
			or tex_path.contains("yaolu_hall")
			or tex_path.contains("alchemy_pavilion")
			or tex_path.contains("ruined_temple")
		)
		if is_arch_bldg or collision_r >= 85.0:
			_mm_buildings.append(Rect2(base_pos.x - tw * 0.36, base_pos.y - th * 0.55, tw * 0.72, th * 0.48))
	_ysort_root.add_child(sp)
	if collision_r > 0.0:
		_combat_ctrl.obstacle_circles.append({"pos": base_pos + Vector2(0.0, -24.0), "radius": collision_r})
	return sp


func _add_ysort_wall_module(tex_path: String, mid_ground_pos: Vector2, flip_x: bool, offset_y: float) -> Sprite2D:
	var sp: Sprite2D = Sprite2D.new()
	sp.position = mid_ground_pos
	sp.centered = false
	sp.flip_h = flip_x
	if ResourceLoader.exists(tex_path):
		var tex: Texture2D = load(tex_path) as Texture2D
		sp.texture = tex
		var tw: float = float(tex.get_width())
		var th: float = float(tex.get_height())
		var safe_off_y: float = clampf(offset_y, -th - 2.0, -th * 0.785)
		sp.offset = Vector2(-tw * 0.5, safe_off_y)
		if tex_path.contains("gatehouse"):
			_occluder_sprites.append({
				"sprite": sp,
				"rect": Rect2(mid_ground_pos.x - tw * 0.36, mid_ground_pos.y + safe_off_y + 10.0, tw * 0.72, th * 0.46),
			})
			_mm_buildings.append(Rect2(mid_ground_pos.x - tw * 0.32, mid_ground_pos.y - th * 0.32, tw * 0.64, th * 0.30))
	_ysort_root.add_child(sp)
	return sp


func _add_ground_decor_prop(tex_path: String, base_pos: Vector2, node_name: String) -> Sprite2D:
	var sp: Sprite2D = Sprite2D.new()
	sp.name = node_name
	sp.position = base_pos
	sp.centered = false
	if ResourceLoader.exists(tex_path):
		var tex: Texture2D = load(tex_path) as Texture2D
		sp.texture = tex
		sp.offset = Vector2(-float(tex.get_width()) * 0.5, -float(tex.get_height()))
	_ground_decor_layer.add_child(sp)
	return sp


func _add_stage_c_point_light(
	pos: Vector2,
	col: Color,
	energy_val: float,
	tex_scale: float,
	flicker_phase: float = -1.0
) -> PointLight2D:
	if _light_radial_tex == null:
		return null
	var pl: PointLight2D = PointLight2D.new()
	pl.name = "StageCPointLight_%d" % _zone_point_lights.size()
	pl.position = pos
	pl.texture = _light_radial_tex
	pl.texture_scale = tex_scale
	pl.color = col
	pl.energy = energy_val
	pl.blend_mode = Light2D.BLEND_MODE_ADD
	pl.range_z_min = -100
	pl.range_z_max = 100
	pl.enabled = true
	_ground_decor_layer.add_child(pl)
	_zone_point_lights.append({
		"light": pl,
		"base_energy": energy_val,
		"flicker_phase": flicker_phase,
	})
	return pl


func _rebuild_foreground_bamboo_leaves(enable_outdoor: bool) -> void:
	_fg_bamboo_leaves.clear()
	if _rain_overlay == null:
		return
	var stale: Array[Node] = []
	for ch: Node in _rain_overlay.get_children():
		stale.append(ch)
	for st: Node in stale:
		_rain_overlay.remove_child(st)
		st.queue_free()
	if not enable_outdoor:
		if CampaignState.current_zone_id == "cangmu_cave" and _fg_cave_stalactite_tex != null:
			# 地底古窟左上穹顶与右下岩角挂载宋明工笔钟乳盘根暗角（严避右上角小地图与左下角小队框，静态微视差不随风摇曳！）
			var cave_presets: Array[Dictionary] = [
				{"corner": Vector2(-1.0, -1.0), "inset": Vector2(102.0, 88.0), "scale": Vector2(0.86, 0.86), "rot": 0.0, "phase": 0.0, "flip_h": true, "flip_v": false},
				{"corner": Vector2(1.0, 1.0), "inset": Vector2(-102.0, -88.0), "scale": Vector2(0.84, 0.84), "rot": 0.0, "phase": 0.0, "flip_h": false, "flip_v": true},
			]
			for ci: int in range(cave_presets.size()):
				var ccfg: Dictionary = cave_presets[ci]
				var csp: Sprite2D = Sprite2D.new()
				csp.name = "FgCaveStalactite_%d" % ci
				csp.texture = _fg_cave_stalactite_tex
				csp.flip_h = bool(ccfg["flip_h"])
				csp.flip_v = bool(ccfg["flip_v"])
				csp.scale = ccfg["scale"] as Vector2
				csp.rotation = float(ccfg["rot"])
				csp.modulate = Color(0.54, 0.60, 0.58, 0.64)
				_rain_overlay.add_child(csp)
				_fg_bamboo_leaves.append({
					"node": csp,
					"corner": ccfg["corner"] as Vector2,
					"inset": ccfg["inset"] as Vector2,
					"base_rot": float(ccfg["rot"]),
					"phase": 0.0,
					"sway": false,
				})
		return
	if _fg_bamboo_tex == null:
		return

	# 严格锚定于视口外框边角（左上角、顶左檐、右下角、右中下缘），竹枝根部全部伸出画框之外，绝不漂移至画幅中央或遮挡 HUD/气泡！
	var presets: Array[Dictionary] = [
		{"corner": Vector2(-1.0, -1.0), "inset": Vector2(88.0, 56.0), "scale": Vector2(1.06, 1.06), "rot": 0.04, "phase": 0.0, "flip_h": false, "flip_v": false},
		{"corner": Vector2(-1.0, -1.0), "inset": Vector2(268.0, 34.0), "scale": Vector2(0.88, 0.88), "rot": -0.14, "phase": 1.6, "flip_h": false, "flip_v": false},
		{"corner": Vector2(1.0, 1.0), "inset": Vector2(-86.0, -54.0), "scale": Vector2(1.04, 1.04), "rot": 0.05, "phase": 3.1, "flip_h": true, "flip_v": true},
		{"corner": Vector2(1.0, 1.0), "inset": Vector2(-78.0, -212.0), "scale": Vector2(0.92, 0.92), "rot": -0.10, "phase": 4.7, "flip_h": true, "flip_v": false},
	]
	for i: int in range(presets.size()):
		var cfg: Dictionary = presets[i]
		var lsp: Sprite2D = Sprite2D.new()
		lsp.name = "FgBambooLeaf_%d" % i
		lsp.texture = _fg_bamboo_tex
		lsp.flip_h = bool(cfg["flip_h"])
		lsp.flip_v = bool(cfg["flip_v"])
		lsp.scale = cfg["scale"] as Vector2
		lsp.rotation = float(cfg["rot"])
		lsp.modulate = Color(0.16, 0.25, 0.21, 0.46)
		_rain_overlay.add_child(lsp)
		_fg_bamboo_leaves.append({
			"node": lsp,
			"corner": cfg["corner"] as Vector2,
			"inset": cfg["inset"] as Vector2,
			"base_rot": float(cfg["rot"]),
			"phase": float(cfg["phase"]),
			"sway": true,
		})


func _sync_foreground_bamboo_positions(_delta: float) -> void:
	if _fg_bamboo_leaves.is_empty() or _camera == null:
		return
	var cam_c: Vector2 = _camera.get_screen_center_position()
	var vp_world: Vector2 = get_viewport_rect().size / _camera.zoom
	if vp_world.x < 200.0 or vp_world.y < 200.0:
		vp_world = Vector2(1920.0, 1080.0)
	var half_vp: Vector2 = vp_world * 0.5
	# 微幅视差严格钳制在 ±12px 内，既响应镜头平移又确保竹枝根部永远紧贴视口边角！
	var micro_parallax: Vector2 = Vector2(
		clampf(-(_camera.position.x - 1200.0) * 0.025, -12.0, 12.0),
		clampf(-(_camera.position.y - 700.0) * 0.025, -10.0, 10.0)
	)
	var sway_on: bool = not SaveManager.reduced_motion
	for entry: Dictionary in _fg_bamboo_leaves:
		var lsp: Sprite2D = entry["node"] as Sprite2D
		if not is_instance_valid(lsp):
			continue
		var corner: Vector2 = entry["corner"] as Vector2
		var inset: Vector2 = entry["inset"] as Vector2
		var ph: float = float(entry["phase"])
		var base_rot: float = float(entry["base_rot"])
		var wind_vec: Vector2 = Vector2.ZERO
		var rot_add: float = 0.0
		if sway_on and bool(entry.get("sway", true)):
			wind_vec = Vector2(sin(_light_flicker_clock * 2.1 + ph) * 7.5, cos(_light_flicker_clock * 1.6 + ph) * 4.0)
			rot_add = sin(_light_flicker_clock * 2.4 + ph) * 0.055
		var edge_anchor: Vector2 = Vector2(corner.x * half_vp.x, corner.y * half_vp.y) + inset
		lsp.position = cam_c + edge_anchor + micro_parallax + wind_vec
		lsp.rotation = base_rot + rot_add


func _step_m4_lighting_and_foreground(delta: float) -> void:
	var target_ripple_spd: float = 0.0 if SaveManager.reduced_motion else 1.0
	for rmat: ShaderMaterial in _wet_road_materials:
		if rmat != null:
			rmat.set_shader_parameter("ripple_speed", target_ripple_spd)

	if not SaveManager.reduced_motion:
		_light_flicker_clock += delta
	for linfo: Dictionary in _zone_point_lights:
		var pl: PointLight2D = linfo["light"] as PointLight2D
		if pl == null or not is_instance_valid(pl):
			continue
		var base_e: float = float(linfo["base_energy"])
		var fphase: float = float(linfo["flicker_phase"])
		if fphase >= 0.0 and not SaveManager.reduced_motion:
			var wave: float = 0.055 * sin(_light_flicker_clock * 4.8 + fphase) + 0.03 * sin(_light_flicker_clock * 8.3 + fphase * 1.7)
			pl.energy = maxf(0.05, base_e * (1.0 + wave))
		else:
			pl.energy = base_e

	_sync_foreground_bamboo_positions(delta)


func _resolve_interactable_plaque_name(id_str: String, fallback_title: String) -> String:
	var key_map: Dictionary = {
		"peddler_stall": "PROP_PEDDLER_STALL_NAME",
		"yaolu_alchemy": "PROP_YAOLU_ALCHEMY_NAME",
		"yaolu_shop": "PROP_YAOLU_SHOP_NAME",
		"yaolu_discarded_pill": "PROP_DISCARDED_BASKET_NAME",
		"herb_town_1": "PROP_HERB_QINGMU_NAME",
		"herb_pass_1": "PROP_HERB_CHIYANG_NAME",
		"herb_cave_stealth": "PROP_HERB_CORRUPT_NAME",
		"stele_tingyu_gate": "PROP_STELE_TINGYU_NAME",
		"stele_temple_courtyard": "PROP_STELE_TEMPLE_NAME",
		"stele_cave_mid": "PROP_STELE_CAVE_MID_NAME",
		"stele_wolf_altar": "PROP_STELE_ALTAR_NAME",
		"injured_beast": "PROP_INJURED_BEAST_NAME",
		"cliff_chest_vista": "PROP_CLIFF_VISTA_NAME",
		"temple_event_trigger": "PROP_TEMPLE_ENTRY_NAME",
		"barrier_vine": "PROP_BARRIER_VINE_NAME",
		"chest_poxue_pendant": "PROP_ANCIENT_CHEST_NAME",
		"ancient_remains": "PROP_ANCIENT_REMAINS_NAME",
		"shortcut_gate": "PROP_SHORTCUT_GATE_NAME",
		"wolf_altar_trigger": "PROP_WOLF_ALTAR_NAME",
	}
	if id_str == "barrier_pool":
		var clean_p: bool = bool(CampaignState.world_flags.get("miasma_pool_cleansed", false))
		return tr("PROP_CLEAN_POOL_NAME" if clean_p else "PROP_MIASMA_POOL_NAME")
	if key_map.has(id_str):
		return tr(str(key_map[id_str]))
	var bracket_i: int = fallback_title.find(" [")
	if bracket_i > 0:
		return fallback_title.substr(0, bracket_i)
	return fallback_title


func _add_interactable(
	id_str: String,
	kind: String,
	pos: Vector2,
	radius: float,
	title: String,
	tex_path: String,
	obs_idx: int = -1,
	is_flat_ground: bool = false
) -> void:
	var sp: Sprite2D = null
	if tex_path != "" and ResourceLoader.exists(tex_path):
		sp = Sprite2D.new()
		sp.position = pos
		sp.centered = false
		var tex: Texture2D = load(tex_path) as Texture2D
		sp.texture = tex
		sp.offset = Vector2(-float(tex.get_width()) * 0.5, -float(tex.get_height()))
		if _hover_outline_shader != null:
			var sm: ShaderMaterial = ShaderMaterial.new()
			sm.shader = _hover_outline_shader
			sm.set_shader_parameter("use_uv_border_clamp", true)
			sm.set_shader_parameter("outline_intensity", 0.0)
			sp.material = sm
		if is_flat_ground:
			_ground_decor_layer.add_child(sp)
		else:
			_ysort_root.add_child(sp)

	if kind == "stele":
		_mm_steles.append(pos)

	_interactables.append({
		"id": id_str,
		"kind": kind,
		"pos": pos,
		"radius": radius,
		"title": title,
		"clean_name": _resolve_interactable_plaque_name(id_str, title),
		"sprite": sp,
		"obstacle_idx": obs_idx,
	})


func _add_zone_portal(rect: Rect2, target_zone: String, target_spawn: String, label_txt: String) -> void:
	_zone_portals.append({
		"rect": rect,
		"target_zone": target_zone,
		"target_spawn": target_spawn,
		"label": label_txt,
	})
	_mm_portals.append(rect.get_center())
	# 走近出口 760px 内平滑浮现古雅路标牌，并实时钳制于当前镜头视口与 HUD 安全区内，彻底根除屏幕边缘半截裁切！
	var marker: Node2D = Node2D.new()
	marker.position = rect.get_center()
	marker.z_index = 2
	marker.draw.connect(func() -> void:
		var cpos: Vector2 = marker.position
		var dist: float = _combat_ctrl.get_controlled_actor_pos().distance_to(cpos)
		if dist > 760.0:
			return
		var fade_a: float = clampf((760.0 - dist) / 170.0, 0.0, 1.0)
		var font: Font = UIThemeBuilder.get_bold_font()
		var w: float = font.get_string_size(label_txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 18).x + 28.0
		var vp_sz: Vector2 = get_viewport_rect().size / _camera.zoom
		var cam_c: Vector2 = _camera.get_screen_center_position()
		var cam_rect: Rect2 = Rect2(cam_c - vp_sz * 0.5, vp_sz)
		var world_x: float = clampf(cpos.x - w * 0.5, maxf(24.0, cam_rect.position.x + 24.0), minf(ZONE_BOUNDS.size.x - w - 24.0, cam_rect.end.x - w - 24.0))
		var world_y: float = clampf(cpos.y - 22.0, maxf(24.0, cam_rect.position.y + 24.0), minf(ZONE_BOUNDS.size.y - 60.0, cam_rect.end.y - 60.0))
		if world_x + w > cam_rect.end.x - 368.0 and world_y < cam_rect.position.y + 266.0:
			world_y = cam_rect.position.y + 268.0
		if world_x < cam_rect.position.x + 340.0 and world_y + 36.0 > cam_rect.end.y - 428.0:
			world_y = cam_rect.end.y - 468.0
		var box: Rect2 = Rect2(world_x - cpos.x, world_y - cpos.y, w, 36.0)
		marker.draw_rect(box, Color(0.12, 0.11, 0.10, 0.92 * fade_a), true)
		marker.draw_rect(box, Color(UIThemeBuilder.COL_BRONZE_GOLD.r, UIThemeBuilder.COL_BRONZE_GOLD.g, UIThemeBuilder.COL_BRONZE_GOLD.b, fade_a), false, 2.0)
		marker.draw_string(font, Vector2(box.position.x + 14.0, box.position.y + 25.0), label_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(UIThemeBuilder.COL_BRONZE_GOLD.r, UIThemeBuilder.COL_BRONZE_GOLD.g, UIThemeBuilder.COL_BRONZE_GOLD.b, fade_a))
	)
	_ground_decor_layer.add_child(marker)
	_portal_markers.append(marker)


func _build_pass_mountain_ravines() -> void:
	# 在两座杉木栈桥正下方绘制自然参差的斧劈皴山涧幽壑、溪石飞泉与流岚雾气！
	var ravine_canvas: Node2D = Node2D.new()
	ravine_canvas.name = "PassMountainRavines"
	ravine_canvas.draw.connect(func() -> void:
		var gorges: Array[Dictionary] = [
			{"top": Vector2(928.0, 645.0), "bot": Vector2(1062.0, 1025.0), "hw": 78.0, "seed": 1.0},
			{"top": Vector2(1338.0, 505.0), "bot": Vector2(1468.0, 865.0), "hw": 76.0, "seed": 2.7},
		]
		for g: Dictionary in gorges:
			var p_top: Vector2 = g["top"] as Vector2
			var p_bot: Vector2 = g["bot"] as Vector2
			var hw: float = float(g["hw"])
			var gseed: float = float(g["seed"])
			var dir_v: Vector2 = (p_bot - p_top).normalized()
			var perp: Vector2 = Vector2(-dir_v.y, dir_v.x)
			var left_rim: PackedVector2Array = PackedVector2Array()
			var right_rim: PackedVector2Array = PackedVector2Array()
			var left_inner: PackedVector2Array = PackedVector2Array()
			var right_inner: PackedVector2Array = PackedVector2Array()
			var n_seg: int = 10
			for si: int in range(n_seg + 1):
				var u: float = float(si) / float(n_seg)
				var taper: float = sin(u * PI) * 0.35 + 0.65
				var jag_l: float = sin(float(si) * 2.3 + gseed) * 14.0
				var jag_r: float = cos(float(si) * 2.1 + gseed * 1.4) * 14.0
				var c_pt: Vector2 = p_top.lerp(p_bot, u)
				left_rim.append(c_pt - perp * (hw * taper + jag_l))
				right_rim.append(c_pt + perp * (hw * taper + jag_r))
				left_inner.append(c_pt - perp * (hw * 0.48 * taper + jag_l * 0.5) + Vector2(0.0, 18.0))
				right_inner.append(c_pt + perp * (hw * 0.48 * taper + jag_r * 0.5) + Vector2(0.0, 18.0))

			var outer_poly: PackedVector2Array = PackedVector2Array()
			outer_poly.append_array(left_rim)
			for ri: int in range(right_rim.size() - 1, -1, -1):
				outer_poly.append(right_rim[ri])
			ravine_canvas.draw_colored_polygon(outer_poly, Color(0.11, 0.15, 0.15, 0.96))

			var stream_poly: PackedVector2Array = PackedVector2Array()
			stream_poly.append_array(left_inner)
			for ri2: int in range(right_inner.size() - 1, -1, -1):
				stream_poly.append(right_inner[ri2])
			ravine_canvas.draw_colored_polygon(stream_poly, Color(0.15, 0.25, 0.26, 0.92))

			# 斧劈皴崖壁立面裂纹与苔石压边
			for si2: int in range(n_seg):
				var lp: Vector2 = left_rim[si2]
				var rp: Vector2 = right_rim[si2]
				ravine_canvas.draw_line(lp, lp + Vector2(6.0, 26.0), Color(0.06, 0.08, 0.08, 0.78), 2.2)
				ravine_canvas.draw_line(rp, rp + Vector2(-6.0, 26.0), Color(0.06, 0.08, 0.08, 0.78), 2.2)
			ravine_canvas.draw_polyline(left_rim, Color(0.28, 0.36, 0.32, 0.94), 5.0)
			ravine_canvas.draw_polyline(right_rim, Color(0.28, 0.36, 0.32, 0.94), 5.0)

			# 涧底飞瀑流泉与桥下轻岚云气
			for fi: int in range(1, n_seg - 1):
				var t0: float = float(fi) / float(n_seg)
				var t1: float = float(fi + 1) / float(n_seg)
				var fa: Vector2 = p_top.lerp(p_bot, t0) + perp * (sin(float(fi) * 1.8 + gseed) * 9.0) + Vector2(0.0, 16.0)
				var fb: Vector2 = p_top.lerp(p_bot, t1) + perp * (sin(float(fi + 1) * 1.8 + gseed) * 9.0) + Vector2(0.0, 16.0)
				ravine_canvas.draw_line(fa, fb, Color(0.58, 0.72, 0.70, 0.36), 9.0)
				ravine_canvas.draw_line(fa - perp * 4.0, fb - perp * 4.0, Color(0.76, 0.86, 0.84, 0.30), 2.5)
			for mu: float in [0.34, 0.66]:
				var mc: Vector2 = p_top.lerp(p_bot, mu)
				var mpts: PackedVector2Array = PackedVector2Array()
				for mk: int in range(16):
					var mang: float = TAU * float(mk) / 16.0
					mpts.append(mc + Vector2(cos(mang) * (hw * 0.82), sin(mang) * 26.0))
				ravine_canvas.draw_colored_polygon(mpts, Color(0.70, 0.82, 0.80, 0.14))
	)
	_ground_base_sub.add_child(ravine_canvas)


func _build_pass_cliff_abyss() -> void:
	# 1. 近岸断崖自然弧形折线与深渊墨色底谷（由南端斜切东北，拉开 430px 云海天堑且无生硬竖切边！）
	var rim_pts: PackedVector2Array = PackedVector2Array([
		Vector2(1175.0, 1400.0),
		Vector2(1230.0, 1170.0),
		Vector2(1290.0, 985.0),
		Vector2(1485.0, 965.0),
		Vector2(1615.0, 815.0),
		Vector2(2400.0, 785.0),
	])
	var abyss_pts: PackedVector2Array = PackedVector2Array()
	for pt: Vector2 in rim_pts:
		abyss_pts.append(pt)
	abyss_pts.append(Vector2(2400.0, 1400.0))

	var abyss_poly: Polygon2D = Polygon2D.new()
	abyss_poly.polygon = abyss_pts
	abyss_poly.color = Color(0.06, 0.09, 0.09, 0.98)
	_ground_decor_layer.add_child(abyss_poly)

	# 2. 断崖立面皴擦岩壁、青苔崩石边沿、流岚云海与对岸百丈孤峰剑台
	var cliff_canvas: Node2D = Node2D.new()
	cliff_canvas.draw.connect(func() -> void:
		# 近岸断崖陡壁下垂立面（斧劈皴深浅两层）
		for seg_i: int in range(rim_pts.size() - 1):
			var a: Vector2 = rim_pts[seg_i]
			var b: Vector2 = rim_pts[seg_i + 1]
			var drop_v: Vector2 = Vector2(36.0, 88.0) if seg_i <= 1 else Vector2(0.0, 92.0)
			var drop_u: Vector2 = Vector2(14.0, 34.0) if seg_i <= 1 else Vector2(0.0, 36.0)
			var wall_deep: PackedVector2Array = PackedVector2Array([
				a, b, b + drop_v, a + drop_v
			])
			cliff_canvas.draw_colored_polygon(wall_deep, Color(0.12, 0.16, 0.16, 0.96))
			var wall_upper: PackedVector2Array = PackedVector2Array([
				a, b, b + drop_u, a + drop_u
			])
			cliff_canvas.draw_colored_polygon(wall_upper, Color(0.18, 0.24, 0.22, 0.96))
			var crags: int = maxi(3, int(floor(a.distance_to(b) / 42.0)))
			for c_i: int in range(crags):
				var t: float = (float(c_i) + 0.5) / float(crags)
				var cp: Vector2 = a.lerp(b, t)
				cliff_canvas.draw_line(cp + Vector2(0.0, 6.0), cp + Vector2(-8.0, 68.0), Color(0.08, 0.11, 0.11, 0.78), 2.5)
				cliff_canvas.draw_rect(Rect2(cp - Vector2(16.0, 6.0), Vector2(32.0, 11.0)), Color(0.28, 0.35, 0.32, 0.95), true)

		# 渊底流岚云气（隔开近岸观景台与对岸孤峰）
		var mist_bands: Array[Dictionary] = [
			{"pos": Vector2(1460.0, 1065.0), "rx": 240.0, "ry": 44.0, "a": 0.18},
			{"pos": Vector2(1620.0, 1005.0), "rx": 210.0, "ry": 38.0, "a": 0.15},
			{"pos": Vector2(1560.0, 1175.0), "rx": 290.0, "ry": 52.0, "a": 0.14},
			{"pos": Vector2(1960.0, 960.0), "rx": 260.0, "ry": 46.0, "a": 0.16},
		]
		for mb: Dictionary in mist_bands:
			var mpos: Vector2 = mb["pos"] as Vector2
			var mrx: float = float(mb["rx"])
			var mry: float = float(mb["ry"])
			var ma: float = float(mb["a"])
			var mpts: PackedVector2Array = PackedVector2Array()
			for k: int in range(20):
				var ang: float = TAU * float(k) / 20.0
				mpts.append(mpos + Vector2(cos(ang) * mrx, sin(ang) * mry))
			cliff_canvas.draw_colored_polygon(mpts, Color(0.72, 0.85, 0.83, ma))

		# 对岸孤峰绝壁石柱与台面（x=1690..1925, y=1025..1130）
		var pillar_trunk: PackedVector2Array = PackedVector2Array([
			Vector2(1695.0, 1095.0), Vector2(1915.0, 1090.0),
			Vector2(1945.0, 1400.0), Vector2(1665.0, 1400.0),
		])
		cliff_canvas.draw_colored_polygon(pillar_trunk, Color(0.13, 0.18, 0.17, 0.98))
		for p_x: int in [1730, 1775, 1825, 1875]:
			cliff_canvas.draw_line(Vector2(float(p_x), 1105.0), Vector2(float(p_x - 14), 1390.0), Color(0.08, 0.11, 0.11, 0.82), 3.0)

		var pinnacle_top: PackedVector2Array = PackedVector2Array([
			Vector2(1715.0, 1035.0), Vector2(1885.0, 1030.0), Vector2(1925.0, 1075.0),
			Vector2(1895.0, 1122.0), Vector2(1720.0, 1126.0), Vector2(1685.0, 1082.0),
		])
		cliff_canvas.draw_colored_polygon(pinnacle_top, Color(0.25, 0.33, 0.29, 0.98))
		for p_i: int in range(pinnacle_top.size()):
			var pa: Vector2 = pinnacle_top[p_i]
			var pb: Vector2 = pinnacle_top[(p_i + 1) % pinnacle_top.size()]
			cliff_canvas.draw_line(pa, pb, Color(0.42, 0.52, 0.47, 0.90), 3.0)
	)
	_ground_decor_layer.add_child(cliff_canvas)

	# 3. 沿近岸整条弧形悬崖边沿铺设严密物理空气墙圆，100% 阻断徒步下渊！
	for seg_i2: int in range(rim_pts.size() - 1):
		_append_wall_segment_obstacles(rim_pts[seg_i2], rim_pts[seg_i2 + 1], 40.0, 44.0)

	# 近岸观景台两侧镇崖巨石 + 对岸孤峰奇石与古修石匣（纯视觉隔渊相望！）
	_add_ysort_structure("res://assets/world/prop_cliff_rock.png", Vector2(1255.0, 985.0), 46.0, false)
	_add_ysort_structure("res://assets/world/prop_cliff_rock.png", Vector2(1540.0, 925.0), 46.0, false)
	_add_ysort_structure("res://assets/world/prop_cliff_rock.png", Vector2(1855.0, 1105.0), 0.0, false)
	if ResourceLoader.exists("res://assets/world/prop_treasure_chest.png"):
		var far_chest: Sprite2D = Sprite2D.new()
		far_chest.position = Vector2(1765.0, 1095.0)
		far_chest.centered = false
		var ctex: Texture2D = load("res://assets/world/prop_treasure_chest.png") as Texture2D
		far_chest.texture = ctex
		far_chest.offset = Vector2(-float(ctex.get_width()) * 0.5, -float(ctex.get_height()))
		_ysort_root.add_child(far_chest)


func _add_cavern_rock_mass(poly: PackedVector2Array) -> void:
	if poly.size() < 3:
		return

	# 1. 将洞内非极边折线细分为自然参差的斧劈皴碎岩轮廓（世界外边界点严格不动，消除 90° 死黑碰撞块！）
	var crag_poly: PackedVector2Array = PackedVector2Array()
	for idx_e: int in range(poly.size()):
		var pa: Vector2 = poly[idx_e]
		var pb: Vector2 = poly[(idx_e + 1) % poly.size()]
		crag_poly.append(pa)
		var is_border_edge: bool = (
			(pa.x <= 1.0 and pb.x <= 1.0)
			or (pa.x >= 2399.0 and pb.x >= 2399.0)
			or (pa.y <= 1.0 and pb.y <= 1.0)
			or (pa.y >= 1399.0 and pb.y >= 1399.0)
		)
		var seg_d: float = pa.distance_to(pb)
		if not is_border_edge and seg_d >= 72.0:
			var ed_v: Vector2 = (pb - pa) / seg_d
			var nrm_v: Vector2 = Vector2(-ed_v.y, ed_v.x)
			if Geometry2D.is_point_in_polygon((pa + pb) * 0.5 + nrm_v * 8.0, poly):
				nrm_v = -nrm_v
			var n_sub: int = maxi(2, int(floor(seg_d / 48.0)))
			for sub_i: int in range(1, n_sub):
				var u: float = float(sub_i) / float(n_sub)
				var base_pt: Vector2 = pa.lerp(pb, u)
				var h1: float = sin(base_pt.x * 0.043 + base_pt.y * 0.031 + float(idx_e * 7 + sub_i * 13))
				var h2: float = cos(base_pt.x * 0.027 - base_pt.y * 0.053 + float(sub_i * 19))
				crag_poly.append(base_pt + nrm_v * (h1 * 11.0 + 3.0) + ed_v * (h2 * 6.0))

	# 2. 玄岩顶盖层挂载暗调无缝石灰岩肌理（不再是死黑纯色 Polygon2D）
	var body: Polygon2D = Polygon2D.new()
	body.polygon = crag_poly
	if ResourceLoader.exists("res://assets/world/tex_cave_flagstone.png"):
		body.texture = load("res://assets/world/tex_cave_flagstone.png") as Texture2D
		body.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		body.color = Color(0.28, 0.32, 0.30, 0.99)
	else:
		body.color = Color(0.11, 0.14, 0.13, 0.99)
	_ground_decor_layer.add_child(body)

	# 3. 沿非世界边界岩沿绘制宋明工笔双层斧劈皴立面断崖、青苔石缝与浓墨勾勒（彻底废除霓虹青双线 Line2D！）
	var cliff_bevel: Node2D = Node2D.new()
	cliff_bevel.draw.connect(func() -> void:
		var n_c: int = crag_poly.size()
		for ci: int in range(n_c):
			var ca: Vector2 = crag_poly[ci]
			var cb: Vector2 = crag_poly[(ci + 1) % n_c]
			if (
				(ca.x <= 2.0 and cb.x <= 2.0)
				or (ca.x >= 2398.0 and cb.x >= 2398.0)
				or (ca.y <= 2.0 and cb.y <= 2.0)
				or (ca.y >= 1398.0 and cb.y >= 1398.0)
			):
				continue
			var clen: float = ca.distance_to(cb)
			if clen < 6.0:
				continue
			var cdir: Vector2 = (cb - ca) / clen
			var cnorm: Vector2 = Vector2(-cdir.y, cdir.x)
			if Geometry2D.is_point_in_polygon((ca + cb) * 0.5 + cnorm * 6.0, crag_poly):
				cnorm = -cnorm
			var drop_vec: Vector2 = cnorm * 16.0 + Vector2(0.0, 9.0)
			var mid_vec: Vector2 = cnorm * 8.5 + Vector2(0.0, 4.5)
			cliff_bevel.draw_colored_polygon(
				PackedVector2Array([ca, cb, cb + drop_vec * 1.45, ca + drop_vec * 1.45]),
				Color(0.04, 0.06, 0.06, 0.54)
			)
			cliff_bevel.draw_colored_polygon(
				PackedVector2Array([ca, cb, cb + drop_vec, ca + drop_vec]),
				Color(0.16, 0.20, 0.19, 0.96)
			)
			var tone_j: float = 0.025 * sin(float(ci * 23) * 1.41)
			cliff_bevel.draw_colored_polygon(
				PackedVector2Array([ca - cnorm * 3.0, cb - cnorm * 3.0, cb + mid_vec, ca + mid_vec]),
				Color(0.23 + tone_j, 0.28 + tone_j, 0.25 + tone_j, 0.95)
			)
			cliff_bevel.draw_line(ca + mid_vec * 0.4, ca + drop_vec, Color(0.08, 0.10, 0.10, 0.80), 1.8)
			cliff_bevel.draw_line(ca, cb, Color(0.09, 0.12, 0.11, 0.92), 2.2)
			cliff_bevel.draw_line(ca + drop_vec, cb + drop_vec, Color(0.07, 0.09, 0.09, 0.88), 1.8)
	)
	_ground_decor_layer.add_child(cliff_bevel)

	for i: int in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		# 跳过外框世界极边以节省无谓碰撞圆，洞内所有岩壁边 100% 密铺阻挡圆！
		var on_world_border: bool = (
			(a.x <= 1.0 and b.x <= 1.0)
			or (a.x >= 2399.0 and b.x >= 2399.0)
			or (a.y <= 1.0 and b.y <= 1.0)
			or (a.y >= 1399.0 and b.y >= 1399.0)
		)
		if not on_world_border:
			_append_wall_segment_obstacles(a, b, 38.0, 44.0)


func _append_wall_segment_obstacles(a: Vector2, b: Vector2, step_px: float, radius_px: float) -> void:
	var dist: float = a.distance_to(b)
	var steps: int = maxi(1, int(ceil(dist / maxf(16.0, step_px))))
	for s_i: int in range(steps + 1):
		var t: float = float(s_i) / float(steps)
		_combat_ctrl.obstacle_circles.append({
			"pos": a.lerp(b, t),
			"radius": radius_px,
		})


func _spawn_npc(npc_id: String, name_str: String, sprite_id: String, pos: Vector2, _tag: String) -> BattleActor:
	var npc: BattleActor = BattleActor.new()
	npc.position = pos
	npc.setup_actor(npc_id, "npc", name_str, sprite_id, 0.96)
	if npc._sprite != null and _hover_outline_shader != null:
		var nsm: ShaderMaterial = ShaderMaterial.new()
		nsm.shader = _hover_outline_shader
		nsm.set_shader_parameter("use_uv_border_clamp", false)
		nsm.set_shader_parameter("outline_intensity", 0.0)
		npc._sprite.material = nsm
	_ysort_root.add_child(npc)
	_npc_actors.append(npc)
	return npc


func _remove_npc_by_id(npc_id: String) -> void:
	for i: int in range(_npc_actors.size() - 1, -1, -1):
		var n: BattleActor = _npc_actors[i]
		if is_instance_valid(n) and n.actor_id == npc_id:
			n.queue_free()
			_npc_actors.remove_at(i)


func _remove_interactable_by_id(id_str: String) -> void:
	for i: int in range(_interactables.size() - 1, -1, -1):
		var inter: Dictionary = _interactables[i]
		if str(inter.get("id", "")) == id_str:
			_remove_interactable_visual(inter)
			_interactables.remove_at(i)
			return


func _remove_interactable_visual(inter: Dictionary) -> void:
	var sp: Sprite2D = inter.get("sprite", null) as Sprite2D
	if sp != null and is_instance_valid(sp):
		sp.queue_free()
	inter["radius"] = 0.0
	inter["title"] = ""


func _clear_obstacle_and_remove(inter: Dictionary) -> void:
	var obs_i: int = int(inter.get("obstacle_idx", -1))
	if obs_i >= 0 and obs_i < _combat_ctrl.obstacle_circles.size():
		_combat_ctrl.obstacle_circles[obs_i] = {"pos": Vector2(-9999.0, -9999.0), "radius": 1.0}
	_remove_interactable_by_id(str(inter.get("id", "")))


func _step_ambient_world_barks(delta: float) -> void:
	if _combat_ctrl.in_combat or _narrative.visible or _modals.visible or _casket.visible:
		return
	_bark_cooldown -= delta
	if _bark_cooldown > 0.0:
		return
	_bark_cooldown = 9.5

	# 同一时刻全屏最多仅允许 1 条世界气泡，彻底杜绝多气泡叠字喧宾夺主！
	for pa_chk_var: Variant in _combat_ctrl.party_actors.values():
		var pa_chk: BattleActor = pa_chk_var as BattleActor
		if is_instance_valid(pa_chk) and pa_chk.has_active_bark():
			return
	for npc_chk: BattleActor in _npc_actors:
		if is_instance_valid(npc_chk) and npc_chk.has_active_bark():
			return

	var ctrl_pos: Vector2 = _combat_ctrl.get_controlled_actor_pos()
	if CampaignState.current_zone_id == "tingyu_town" and not _npc_actors.is_empty():
		var nearby_npcs: Array[BattleActor] = []
		for cand: BattleActor in _npc_actors:
			if is_instance_valid(cand) and cand.position.distance_to(ctrl_pos) <= 640.0:
				nearby_npcs.append(cand)
		if nearby_npcs.is_empty():
			return
		var pick: BattleActor = nearby_npcs[randi() % nearby_npcs.size()]
		if pick.actor_id == "shen_npc":
			pick.show_world_bark(tr("BARK_SHEN_1"), 4.0)
		elif pick.actor_id == "npc_zhou":
			pick.show_world_bark(tr("BARK_ZHOU_1"), 4.0)
		else:
			var keys: Array[String] = ["BARK_TOWN_1", "BARK_TOWN_2", "BARK_TOWN_3"]
			pick.show_world_bark(tr(keys[randi() % keys.size()]), 4.0)
	elif CampaignState.current_zone_id == "cangmu_cave":
		var ctrl_a: BattleActor = _combat_ctrl.get_controlled_actor()
		if (
			ctrl_a != null
			and not bool(CampaignState.world_flags.get("vine_wall_burned", false))
			and ctrl_a.position.distance_to(Vector2(640.0, 1085.0)) <= 320.0
		):
			ctrl_a.show_world_bark(tr("BARK_CAVE_1"), 3.5)


func _draw_atmosphere_rain() -> void:
	if CampaignState.current_zone_id == "cangmu_cave" or SaveManager.reduced_motion:
		return
	for rp: Vector2 in _rain_streaks:
		_rain_overlay.draw_line(rp, rp + Vector2(-14.0, 38.0), Color(0.78, 0.86, 0.88, 0.24), 1.6)


func _draw_xuan_plaque_at(center_pt: Vector2, text_str: String, is_hovered: bool) -> void:
	if _alt_nameplate_overlay == null or text_str == "":
		return
	var font: Font = UIThemeBuilder.get_bold_font()
	if font == null:
		font = ThemeDB.fallback_font
	var text_w: float = font.get_string_size(text_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var bw: float = maxf(116.0, text_w + 34.0)
	var bh: float = 30.0
	var bx: float = center_pt.x - bw * 0.5
	var by: float = center_pt.y - bh * 0.5
	var rect: Rect2 = Rect2(bx, by, bw, bh)

	if _xuan_nameplate_tex != null:
		_alt_nameplate_overlay.draw_texture_rect(_xuan_nameplate_tex, rect.grow(2.0), false)
	else:
		_alt_nameplate_overlay.draw_rect(Rect2(bx + 2.0, by + 3.0, bw, bh), Color(0.06, 0.05, 0.04, 0.52), true)
		_alt_nameplate_overlay.draw_rect(rect, Color("#ECE3D3"), true)
		_alt_nameplate_overlay.draw_rect(rect, UIThemeBuilder.COL_BRONZE_GOLD if is_hovered else Color("#5A3E28"), false, 2.0)
		_alt_nameplate_overlay.draw_rect(rect.grow(-3.0), Color("#B69766"), false, 1.0)

	if is_hovered:
		_alt_nameplate_overlay.draw_rect(rect, UIThemeBuilder.COL_BRONZE_GOLD, false, 2.0)

	# 左侧朱砂菱形小印
	var seal_c: Vector2 = Vector2(bx + 12.0, center_pt.y)
	var seal_pts: PackedVector2Array = PackedVector2Array([
		seal_c + Vector2(0.0, -4.2),
		seal_c + Vector2(4.2, 0.0),
		seal_c + Vector2(0.0, 4.2),
		seal_c + Vector2(-4.2, 0.0),
	])
	_alt_nameplate_overlay.draw_colored_polygon(seal_pts, Color("#B84332"))
	_alt_nameplate_overlay.draw_string(
		font,
		Vector2(bx + 22.0, by + 21.0),
		text_str,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		16,
		Color("#201B18")
	)


func _append_actor_bark_world_rect(actor: BattleActor, font: Font, out_rects: Array[Rect2]) -> void:
	if not is_instance_valid(actor) or not actor.has_active_bark():
		return
	var head_h_b: float = 136.0
	if actor._sprite != null:
		head_h_b = float(actor._head_top_px) * actor._sprite.scale.y
	var single_w: float = font.get_string_size(actor._bark_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var wrap_w: float = minf(272.0, maxf(116.0, single_w + 8.0))
	var box_w: float = wrap_w + 26.0
	var box_h: float = 54.0
	var anchor_y: float = -head_h_b - 46.0
	var bark_r: Rect2 = Rect2(actor.position.x - box_w * 0.5, actor.position.y + anchor_y - box_h - 8.0, box_w, box_h + 12.0).grow(4.0)
	out_rects.append(bark_r)


func _draw_alt_xuan_nameplates() -> void:
	if _alt_nameplate_overlay == null:
		return
	if not _is_alt_highlight_active():
		return

	var font: Font = UIThemeBuilder.get_bold_font()
	if font == null:
		font = ThemeDB.fallback_font
	var placed_rects: Array[Rect2] = []

	var inv_vp: Transform2D = get_canvas_transform().affine_inverse()
	var vp_world_tl: Vector2 = inv_vp * Vector2(12.0, 12.0)
	var vp_world_br: Vector2 = inv_vp * Vector2(1908.0, 1068.0)
	var vp_min_x: float = minf(vp_world_tl.x, vp_world_br.x)
	var vp_max_x: float = maxf(vp_world_tl.x, vp_world_br.x)

	# 预留当前可见 HUD [F] 近距交互提示框与头顶宣纸气泡的世界空间矩形，确保 Alt 题签自动上移避让零遮挡！
	if _hud != null and _hud._interact_prompt_box != null and _hud._interact_prompt_box.visible:
		var p_srect: Rect2 = _hud._interact_prompt_box.get_global_rect()
		var p_min_sz: Vector2 = _hud._interact_prompt_box.get_combined_minimum_size()
		p_srect.size.x = maxf(p_srect.size.x, p_min_sz.x)
		p_srect.size.y = maxf(p_srect.size.y, maxf(40.0, p_min_sz.y))
		var p_tl: Vector2 = inv_vp * p_srect.position
		var p_br: Vector2 = inv_vp * p_srect.end
		placed_rects.append(Rect2(p_tl, p_br - p_tl).abs().grow(4.0))

	if _combat_ctrl != null:
		for pa_var_b: Variant in _combat_ctrl.party_actors.values():
			if pa_var_b != null and is_instance_valid(pa_var_b):
				_append_actor_bark_world_rect(pa_var_b as BattleActor, font, placed_rects)
	for npc_b: BattleActor in _npc_actors:
		_append_actor_bark_world_rect(npc_b, font, placed_rects)

	for inter: Dictionary in _interactables:
		if float(inter.get("radius", 0.0)) <= 0.0 or str(inter.get("title", "")) == "":
			continue
		var iid: String = str(inter.get("id", ""))
		var clean_name: String = _resolve_interactable_plaque_name(iid, str(inter.get("title", "")))
		var ipos: Vector2 = inter.get("pos", Vector2.ZERO) as Vector2
		var raw_sp_a: Variant = inter.get("sprite", null)
		var sp: Sprite2D = (raw_sp_a as Sprite2D) if (raw_sp_a != null and is_instance_valid(raw_sp_a)) else null
		var tex_h: float = 140.0
		if sp != null and sp.texture != null:
			tex_h = float(sp.texture.get_height())
		var center_y: float = ipos.y - clampf(tex_h * 0.78, 88.0, 142.0)
		var est_w: float = maxf(116.0, font.get_string_size(clean_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 34.0)
		var plaque_cx: float = ipos.x
		if ipos.x >= vp_min_x - 36.0 and ipos.x <= vp_max_x + 36.0 and (vp_max_x - vp_min_x) > est_w + 16.0:
			plaque_cx = clampf(ipos.x, vp_min_x + est_w * 0.5, vp_max_x - est_w * 0.5)
		var cand_r: Rect2 = Rect2(plaque_cx - est_w * 0.5, center_y - 16.0, est_w, 32.0)
		for _guard_i: int in range(4):
			var hit_prev: bool = false
			for pr: Rect2 in placed_rects:
				if cand_r.intersects(pr):
					hit_prev = true
					break
			if not hit_prev:
				break
			center_y -= 34.0
			cand_r.position.y = center_y - 16.0
		placed_rects.append(cand_r)
		_draw_xuan_plaque_at(Vector2(plaque_cx, center_y), clean_name, iid == _hovered_interactable_id)

	for npc: BattleActor in _npc_actors:
		if not is_instance_valid(npc):
			continue
		var head_h: float = 136.0
		if npc._sprite != null:
			head_h = float(npc._head_top_px) * npc._sprite.scale.y
		var npc_cy: float = npc.position.y - head_h - 22.0
		var npc_w: float = maxf(116.0, font.get_string_size(npc.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 34.0)
		var npc_cx: float = npc.position.x
		if npc.position.x >= vp_min_x - 36.0 and npc.position.x <= vp_max_x + 36.0 and (vp_max_x - vp_min_x) > npc_w + 16.0:
			npc_cx = clampf(npc.position.x, vp_min_x + npc_w * 0.5, vp_max_x - npc_w * 0.5)
		var npc_r: Rect2 = Rect2(npc_cx - npc_w * 0.5, npc_cy - 16.0, npc_w, 32.0)
		for _guard_j: int in range(4):
			var hit_n: bool = false
			for pr2: Rect2 in placed_rects:
				if npc_r.intersects(pr2):
					hit_n = true
					break
			if not hit_n:
				break
			npc_cy -= 34.0
			npc_r.position.y = npc_cy - 16.0
		placed_rects.append(npc_r)
		_draw_xuan_plaque_at(Vector2(npc_cx, npc_cy), npc.display_name, npc.is_hovered)

