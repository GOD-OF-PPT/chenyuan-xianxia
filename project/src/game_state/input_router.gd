extends Node
## 第二层状态服务单例（3/5）：唯一纯正 PC 键鼠全局输入路由（明确不做任何手柄适配）
## 严格对齐 docs/design/21-ui-ux-spec.md 第 3.4 节与 AGENTS.md 铁律：
## - Space 唯一绑定战斗【战术凝时】，在对话与一切模态框内 100% 拦截屏蔽！
## - 对话推进唯一锁定为 Enter 或鼠标左键点击对话栏，并强制执行 400ms 防连点保护锁！
## - 左键绝不绑定挥剑普攻。

signal tactical_pause_toggled()
signal skill_hotkey_pressed(slot_code: String)
signal party_select_pressed(party_slot: int, double_tap: bool)
signal pet_skill_pressed(pet_slot: int)
signal quick_drawer_toggled()
signal target_tab_pressed()
signal interact_pressed()
signal map_toggled()
signal dao_casket_tab_requested(tab_id: String)
signal dialogue_advance_requested()
signal escape_pressed()
signal alt_highlight_changed(active: bool)
signal keybinds_updated()

const MODE_WORLD_COMBAT: int = 0
const MODE_DIALOGUE: int = 1
const MODE_MODAL_MENU: int = 2
const MODE_CUTSCENE_CG: int = 3
const MODE_BREW_MINIGAME: int = 4

const DIALOGUE_LOCK_DURATION_SEC: float = 0.40
const DOUBLE_TAP_WINDOW_SEC: float = 0.30

const DEFAULT_KEYBINDS: Dictionary = {
	"move_up": KEY_W,
	"move_down": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"tactical_pause": KEY_SPACE,
	"cycle_target": KEY_TAB,
	"skill_1": KEY_1,
	"skill_2": KEY_2,
	"skill_3": KEY_3,
	"skill_4": KEY_4,
	"skill_q": KEY_Q,
	"skill_e": KEY_E,
	"skill_r": KEY_R,
	"skill_g": KEY_G,
	"pill_5": KEY_5,
	"pill_6": KEY_6,
	"drawer_z": KEY_Z,
	"interact": KEY_F,
	"world_map": KEY_M,
	"casket_cultivation": KEY_C,
	"casket_specialization": KEY_N,
	"casket_inventory": KEY_B,
	"casket_journal": KEY_J,
	"dialogue_confirm": KEY_ENTER,
}

var current_mode: int = MODE_WORLD_COMBAT
var combat_engaged: bool = false
var keybinds: Dictionary = {}
var alt_held: bool = false

var _dialogue_cooldown_sec: float = 0.0
var _last_f_slot: int = -1
var _last_f_tap_time: float = 0.0
var _clock: float = 0.0


func _ready() -> void:
	reset_default_keybinds()


func _process(delta: float) -> void:
	_clock += delta
	if _dialogue_cooldown_sec > 0.0:
		_dialogue_cooldown_sec = maxf(0.0, _dialogue_cooldown_sec - delta)
	var now_alt: bool = current_mode == MODE_WORLD_COMBAT and Input.is_key_pressed(KEY_ALT)
	if now_alt != alt_held:
		alt_held = now_alt
		alt_highlight_changed.emit(alt_held)


func set_mode(new_mode: int) -> void:
	current_mode = new_mode
	if new_mode == MODE_DIALOGUE or new_mode == MODE_MODAL_MENU or new_mode == MODE_CUTSCENE_CG:
		_dialogue_cooldown_sec = DIALOGUE_LOCK_DURATION_SEC
		if alt_held:
			alt_held = false
			alt_highlight_changed.emit(false)


func trigger_dialogue_lock() -> void:
	_dialogue_cooldown_sec = DIALOGUE_LOCK_DURATION_SEC


func can_advance_dialogue() -> bool:
	return _dialogue_cooldown_sec <= 0.0


func get_movement_vector() -> Vector2:
	if current_mode != MODE_WORLD_COMBAT:
		return Vector2.ZERO
	var vec: Vector2 = Vector2.ZERO
	if Input.is_physical_key_pressed(int(keybinds.get("move_left", KEY_A)) as Key):
		vec.x -= 1.0
	if Input.is_physical_key_pressed(int(keybinds.get("move_right", KEY_D)) as Key):
		vec.x += 1.0
	if Input.is_physical_key_pressed(int(keybinds.get("move_up", KEY_W)) as Key):
		vec.y -= 1.0
	if Input.is_physical_key_pressed(int(keybinds.get("move_down", KEY_S)) as Key):
		vec.y += 1.0
	if vec.length_squared() > 1.0:
		vec = vec.normalized()
	return vec


func _input(event: InputEvent) -> void:
	# 严禁任何手柄事件混入（纯正 PC 键鼠原生设计）
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()
		return

	if not (event is InputEventKey):
		return
	var kev: InputEventKey = event as InputEventKey
	if not kev.pressed or kev.echo:
		# 允许长按 Ctrl 快进已读对白由演剧台自行轮询 Input.is_key_pressed(KEY_CTRL)
		return

	var code: Key = kev.physical_keycode if kev.physical_keycode != KEY_NONE else kev.keycode

	# 铁律：在对话、确认弹窗、道匣菜单与 CG 期间，100% 吞掉 Space 键，杜绝 Godot 默认 ui_accept 串键！
	if code == KEY_SPACE and current_mode != MODE_WORLD_COMBAT:
		get_viewport().set_input_as_handled()
		return

	if code == KEY_ESCAPE:
		escape_pressed.emit()
		get_viewport().set_input_as_handled()
		return

	if current_mode == MODE_DIALOGUE or current_mode == MODE_CUTSCENE_CG:
		if code == KEY_ENTER or code == KEY_KP_ENTER:
			if can_advance_dialogue():
				dialogue_advance_requested.emit()
		# 对话期间彻底屏蔽战斗与菜单键位
		get_viewport().set_input_as_handled()
		return

	if current_mode == MODE_BREW_MINIGAME:
		return

	if current_mode == MODE_MODAL_MENU:
		# 允许按同一功能页签热键快速切换页签或关闭道匣
		var tab_hit: String = _match_casket_hotkey(code)
		if tab_hit != "":
			dao_casket_tab_requested.emit(tab_hit)
			get_viewport().set_input_as_handled()
		return

	# ==================== MODE_WORLD_COMBAT ====================
	if kev.ctrl_pressed:
		if code == KEY_1:
			pet_skill_pressed.emit(1)
			get_viewport().set_input_as_handled()
			return
		elif code == KEY_2:
			pet_skill_pressed.emit(2)
			get_viewport().set_input_as_handled()
			return

	if code == KEY_F1 or code == KEY_F2 or code == KEY_F3 or code == KEY_F4:
		var slot_num: int = 1
		if code == KEY_F2:
			slot_num = 2
		elif code == KEY_F3:
			slot_num = 3
		elif code == KEY_F4:
			slot_num = 4
		var is_double: bool = (_last_f_slot == slot_num) and ((_clock - _last_f_tap_time) <= DOUBLE_TAP_WINDOW_SEC)
		_last_f_slot = slot_num
		_last_f_tap_time = _clock
		party_select_pressed.emit(slot_num, is_double)
		get_viewport().set_input_as_handled()
		return

	if int(code) == int(keybinds.get("tactical_pause", KEY_SPACE)):
		tactical_pause_toggled.emit()
		get_viewport().set_input_as_handled()
		return

	if int(code) == int(keybinds.get("cycle_target", KEY_TAB)):
		target_tab_pressed.emit()
		get_viewport().set_input_as_handled()
		return

	if int(code) == int(keybinds.get("interact", KEY_F)):
		interact_pressed.emit()
		get_viewport().set_input_as_handled()
		return

	if int(code) == int(keybinds.get("world_map", KEY_M)):
		map_toggled.emit()
		get_viewport().set_input_as_handled()
		return

	if int(code) == int(keybinds.get("drawer_z", KEY_Z)):
		quick_drawer_toggled.emit()
		get_viewport().set_input_as_handled()
		return

	var casket_tab: String = _match_casket_hotkey(code)
	if casket_tab != "":
		dao_casket_tab_requested.emit(casket_tab)
		get_viewport().set_input_as_handled()
		return

	var skill_map: Dictionary = {
		"skill_1": "1",
		"skill_2": "2",
		"skill_3": "3",
		"skill_4": "4",
		"skill_q": "Q",
		"skill_e": "E",
		"skill_r": "R",
		"skill_g": "G",
		"pill_5": "5",
		"pill_6": "6",
	}
	for action_id_var: Variant in skill_map.keys():
		var aid: String = str(action_id_var)
		if int(code) == int(keybinds.get(aid, KEY_NONE)):
			skill_hotkey_pressed.emit(str(skill_map[aid]))
			get_viewport().set_input_as_handled()
			return


func reset_default_keybinds() -> void:
	keybinds = DEFAULT_KEYBINDS.duplicate()
	keybinds_updated.emit()


func check_key_conflict(action_id: String, new_key: int) -> String:
	if new_key == KEY_SPACE and action_id == "dialogue_confirm":
		return "FORBIDDEN_SPACE_DIALOGUE"
	if new_key == KEY_ENTER and action_id != "dialogue_confirm":
		return "dialogue_confirm"
	for existing_var: Variant in keybinds.keys():
		var existing_action: String = str(existing_var)
		if existing_action != action_id and int(keybinds[existing_action]) == new_key:
			return existing_action
	return ""


func rebind_action(action_id: String, new_key: int) -> Dictionary:
	var conflict: String = check_key_conflict(action_id, new_key)
	if conflict != "":
		return {"ok": false, "conflict": conflict}
	keybinds[action_id] = new_key
	keybinds_updated.emit()
	return {"ok": true, "conflict": ""}


func get_key_label(action_id: String) -> String:
	var k: int = int(keybinds.get(action_id, KEY_NONE))
	if k == KEY_NONE:
		return "-"
	return OS.get_keycode_string(k as Key)


func export_keybinds_dict() -> Dictionary:
	return keybinds.duplicate()


func import_keybinds_dict(saved: Dictionary) -> void:
	reset_default_keybinds()
	for k_var: Variant in saved.keys():
		var k_str: String = str(k_var)
		if DEFAULT_KEYBINDS.has(k_str):
			var code_val: int = int(saved[k_str])
			if check_key_conflict(k_str, code_val) == "":
				keybinds[k_str] = code_val
	keybinds_updated.emit()


func _match_casket_hotkey(code: Key) -> String:
	if int(code) == int(keybinds.get("casket_cultivation", KEY_C)):
		return "cultivation"
	if int(code) == int(keybinds.get("casket_specialization", KEY_N)):
		return "specialization"
	if int(code) == int(keybinds.get("casket_inventory", KEY_B)):
		return "inventory"
	if int(code) == int(keybinds.get("casket_journal", KEY_J)):
		return "journal"
	return ""
