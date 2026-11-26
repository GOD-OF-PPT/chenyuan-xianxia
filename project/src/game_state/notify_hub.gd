extends Node
## 第二层状态服务单例（2/5）：唯一四级通知中枢（Notification Arbiter）
## 严格对齐 docs/design/21-ui-ux-spec.md 第 3.3 节：
## P0 系统危机（立即弹窗） / P1 战斗核心反馈（AoE 归并跳字） / P2 叙事独占（清空 P1、冻结 P3） / P3 探索收获轻签（脱战/对话后 1.0s 最多同屏 2 条）。

signal crisis_alert_requested(payload: Dictionary)
signal combat_banner_pushed(payload: Dictionary)
signal combat_floater_pushed(payload: Dictionary)
signal clear_combat_floaters_requested()
signal explore_slip_spawned(payload: Dictionary)

const P0_CRISIS: int = 0
const P1_COMBAT: int = 1
const P2_NARRATIVE: int = 2
const P3_EXPLORE: int = 3

const POST_BUSY_DELAY_SEC: float = 1.0
const SLIP_DURATION_SEC: float = 3.2
const MAX_ACTIVE_SLIPS: int = 2
const AOE_MERGE_WINDOW_SEC: float = 0.09

var combat_active: bool = false
var narrative_exclusive: bool = false
var _post_busy_timer: float = 0.0
var _active_slip_timers: Array[float] = []
var _p3_queue: Array[Dictionary] = []
var _aoe_buckets: Dictionary = {}


func _process(delta: float) -> void:
	# 1. 结算 AoE 归并跳字桶（避免同技能多段碎数字瀑布糊屏）
	if not _aoe_buckets.is_empty():
		var expired_keys: Array[String] = []
		for key_var: Variant in _aoe_buckets.keys():
			var bkey: String = str(key_var)
			var bucket: Dictionary = _aoe_buckets[bkey] as Dictionary
			var rem: float = float(bucket.get("timer", 0.0)) - delta
			bucket["timer"] = rem
			if rem <= 0.0:
				expired_keys.append(bkey)
		for ekey: String in expired_keys:
			var done: Dictionary = _aoe_buckets[ekey] as Dictionary
			_aoe_buckets.erase(ekey)
			if not narrative_exclusive:
				combat_floater_pushed.emit(done)

	# 2. 维护右侧宣纸轻签存活计时
	for i: int in range(_active_slip_timers.size() - 1, -1, -1):
		_active_slip_timers[i] -= delta
		if _active_slip_timers[i] <= 0.0:
			_active_slip_timers.remove_at(i)

	# 3. P3 队列仅在非战斗且非立绘对话独占 1.0 秒后出队，最多同屏 2 条
	if combat_active or narrative_exclusive:
		_post_busy_timer = POST_BUSY_DELAY_SEC
		return

	if _post_busy_timer > 0.0:
		_post_busy_timer = maxf(0.0, _post_busy_timer - delta)
		return

	while not _p3_queue.is_empty() and _active_slip_timers.size() < MAX_ACTIVE_SLIPS:
		var next_slip: Dictionary = _p3_queue.pop_front()
		_active_slip_timers.append(SLIP_DURATION_SEC)
		explore_slip_spawned.emit(next_slip)


func set_combat_active(active: bool) -> void:
	if combat_active == active:
		return
	combat_active = active
	if not active:
		_post_busy_timer = POST_BUSY_DELAY_SEC


func set_narrative_exclusive(exclusive: bool) -> void:
	if narrative_exclusive == exclusive:
		return
	narrative_exclusive = exclusive
	if exclusive:
		_aoe_buckets.clear()
		clear_combat_floaters_requested.emit()
	else:
		_post_busy_timer = POST_BUSY_DELAY_SEC


func clear_all_transient() -> void:
	_aoe_buckets.clear()
	clear_combat_floaters_requested.emit()


## P0：系统级危机警报（如损坏存档零覆盖保护）
func push_crisis(title_text: String, body_text: String, slot_id: String = "", has_backup: bool = false) -> void:
	crisis_alert_requested.emit({
		"priority": P0_CRISIS,
		"title": title_text,
		"body": body_text,
		"slot_id": slot_id,
		"has_backup": has_backup,
	})


## P1：战斗关键机制提示（破罡、相生连携、成功打断、双人合击）
func push_combat_banner(text: String, category: String = "synergy", element: String = "none") -> void:
	if narrative_exclusive:
		return
	combat_banner_pushed.emit({
		"priority": P1_COMBAT,
		"text": text,
		"category": category,
		"element": element,
	})


## P1：战斗伤害/治疗跳字（支持同技能多目标 AoE 自动合并）
func push_combat_number(
	world_pos: Vector2,
	amount: int,
	is_heal: bool,
	is_crit: bool,
	element: String = "none",
	merge_skill_id: String = "",
	prefix_label: String = ""
) -> void:
	if narrative_exclusive or amount <= 0:
		return
	if merge_skill_id != "" and not is_heal:
		if _aoe_buckets.has(merge_skill_id):
			var b: Dictionary = _aoe_buckets[merge_skill_id] as Dictionary
			b["amount"] = int(b.get("amount", 0)) + amount
			b["hit_count"] = int(b.get("hit_count", 1)) + 1
			b["is_crit"] = bool(b.get("is_crit", false)) or is_crit
			b["world_pos"] = (b.get("world_pos", world_pos) as Vector2).lerp(world_pos, 0.35)
			return
		_aoe_buckets[merge_skill_id] = {
			"timer": AOE_MERGE_WINDOW_SEC,
			"world_pos": world_pos,
			"amount": amount,
			"hit_count": 1,
			"is_heal": false,
			"is_crit": is_crit,
			"element": element,
			"prefix_label": prefix_label,
		}
		return

	combat_floater_pushed.emit({
		"world_pos": world_pos,
		"amount": amount,
		"hit_count": 1,
		"is_heal": is_heal,
		"is_crit": is_crit,
		"element": element,
		"prefix_label": prefix_label,
	})


## P3：探索与收获宣纸轻签（拾取灵石丹材、手札线索更新、声望羁绊提升）
func push_explore_slip(title_text: String, detail_text: String = "", tag: String = "loot") -> void:
	# 合并队列内完全相同的连续拾取项
	for raw_item: Variant in _p3_queue:
		if raw_item is Dictionary:
			var existing: Dictionary = raw_item as Dictionary
			if str(existing.get("title", "")) == title_text and str(existing.get("detail", "")) == detail_text:
				return
	_p3_queue.append({
		"priority": P3_EXPLORE,
		"title": title_text,
		"detail": detail_text,
		"tag": tag,
	})
