class_name FormationRules
extends RefCounted
## 第一层核心规则：奇门常驻光环五阵、1~4号四象阵位职责加成与阵阵相克博弈
## 严格对齐 docs/design/01-world-bible.md 与 10-combat-system.md 第 3.5 节（不画地为牢，全队走位自由）。

const FORMATION_SWITCH_COOLDOWN_SEC: float = 45.0

## 大克闭环：天覆 -> 地载 -> 风扬 -> 虎翼 -> 龙飞 -> 天覆（+10% 伤害 / -10% 承伤）
const MAJOR_COUNTER_MAP: Dictionary = {
	"tianfu": "dizai",
	"dizai": "fengyang",
	"fengyang": "huyi",
	"huyi": "longfei",
	"longfei": "tianfu",
}

## 小克映射（+5% 伤害 / -5% 承伤）
const MINOR_COUNTER_MAP: Dictionary = {
	"tianfu": "huyi",
	"dizai": "longfei",
	"fengyang": "tianfu",
	"huyi": "dizai",
	"longfei": "fengyang",
}


static func get_slot_modifiers(formation_def: Dictionary, slot_index: int) -> Dictionary:
	var clamped_slot: int = clampi(slot_index, 1, 4)
	var key: String = "slot_%d" % clamped_slot
	var slots_dict: Dictionary = _as_dict(formation_def.get("slots", {}))
	var raw_slot: Dictionary = _as_dict(slots_dict.get(key, {}))
	return {
		"slot_index": clamped_slot,
		"role_title": str(raw_slot.get("role_title", "青龙位")),
		"damage_mult": float(raw_slot.get("damage_mult", 1.0)),
		"heal_mult": float(raw_slot.get("heal_mult", 1.0)),
		"damage_taken_mult": float(raw_slot.get("damage_taken_mult", 1.0)),
		"move_speed_mult": float(raw_slot.get("move_speed_mult", 1.0)),
		"threat_mult": float(raw_slot.get("threat_mult", 1.0)),
		"haste_bonus": float(raw_slot.get("haste_bonus", 0.0)),
		"crit_bonus": float(raw_slot.get("crit_bonus", 0.0)),
		"ward_break_bonus": float(raw_slot.get("ward_break_bonus", 0.0)),
	}


static func evaluate_counter(attacker_formation_id: String, defender_formation_id: String) -> Dictionary:
	if attacker_formation_id == "" or defender_formation_id == "":
		return _neutral_counter()
	if attacker_formation_id == "scatter" or defender_formation_id == "scatter":
		return _neutral_counter()
	if attacker_formation_id == defender_formation_id:
		return _neutral_counter()

	if str(MAJOR_COUNTER_MAP.get(attacker_formation_id, "")) == defender_formation_id:
		return {
			"relation": "major_advantage",
			"damage_mult": 1.10,
			"damage_taken_mult": 0.90,
			"label_key": "UI_FORM_MAJOR_ADV",
		}
	if str(MAJOR_COUNTER_MAP.get(defender_formation_id, "")) == attacker_formation_id:
		return {
			"relation": "major_disadvantage",
			"damage_mult": 0.90,
			"damage_taken_mult": 1.10,
			"label_key": "UI_FORM_MAJOR_DIS",
		}
	if str(MINOR_COUNTER_MAP.get(attacker_formation_id, "")) == defender_formation_id:
		return {
			"relation": "minor_advantage",
			"damage_mult": 1.05,
			"damage_taken_mult": 0.95,
			"label_key": "UI_FORM_MINOR_ADV",
		}
	if str(MINOR_COUNTER_MAP.get(defender_formation_id, "")) == attacker_formation_id:
		return {
			"relation": "minor_disadvantage",
			"damage_mult": 0.95,
			"damage_taken_mult": 1.05,
			"label_key": "UI_FORM_MINOR_DIS",
		}
	return _neutral_counter()


static func can_switch_formation_in_combat(cooldown_remaining: float, target_formation_id: String, current_formation_id: String, unlocked_ids: Array) -> bool:
	if target_formation_id == "" or target_formation_id == current_formation_id:
		return false
	if cooldown_remaining > 0.0:
		return false
	for raw_id: Variant in unlocked_ids:
		if str(raw_id) == target_formation_id:
			return true
	return false


static func _neutral_counter() -> Dictionary:
	return {
		"relation": "neutral",
		"damage_mult": 1.0,
		"damage_taken_mult": 1.0,
		"label_key": "UI_FORM_NEUTRAL",
	}


static func _as_dict(val: Variant) -> Dictionary:
	if val is Dictionary:
		return val as Dictionary
	return {}
