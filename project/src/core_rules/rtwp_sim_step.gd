class_name RtwpSimStep
extends RefCounted
## 第一层核心规则：无缝 RTwP 逻辑时钟步进结算核（combat_delta 确定性计算）
## 涵盖：1.5s GCD 与 Off-GCD、琥珀金/暗红吟唱与打断封脉、杀意仇恨防抖表（110%/130% OT）、
## 正五行相克破罡（6s 破绽窗口）、五行相生 6s 母印连携引爆、双人合击与败北最后 5 秒致死溯源。
## 纯 RefCounted，0 Node2D/Control 引用，完全支持 Space【战术凝时】0.0 倍速冻结与指令预排。

const MOTHER_SEAL_DURATION_SEC: float = 6.0
const STAGGER_DURATION_SEC: float = 6.0
const STAGGER_STUN_SEC: float = 2.0
const INTERRUPT_LOCKOUT_SEC: float = 3.0
const PILL_TOXICITY_COOLDOWN_SEC: float = 30.0
const PREEMPTIVE_PULL_DURATION_SEC: float = 4.0
const MAX_ATTUNEMENT: float = 100.0
const SYNERGY_ATTUNEMENT_GAIN: float = 15.0
const MELEE_OT_RATIO: float = 1.10
const RANGED_OT_RATIO: float = 1.30
const DEATH_LOG_WINDOW_SEC: float = 5.0

## 五行相克闭环：金克木 -> 木克土 -> 土克水 -> 水克火 -> 火克金
const ELEMENT_COUNTER_MAP: Dictionary = {
	"metal": "wood",
	"wood": "earth",
	"earth": "water",
	"water": "fire",
	"fire": "metal",
}

## 五行相生闭环：木生火 -> 火生土 -> 土生金 -> 金生水 -> 水生木
const ELEMENT_SYNERGY_MAP: Dictionary = {
	"wood": {"child": "fire", "id": "wood_fire", "title_key": "SYN_WOOD_FIRE"},
	"fire": {"child": "earth", "id": "fire_earth", "title_key": "SYN_FIRE_EARTH"},
	"earth": {"child": "metal", "id": "earth_metal", "title_key": "SYN_EARTH_METAL"},
	"metal": {"child": "water", "id": "metal_water", "title_key": "SYN_METAL_WATER"},
	"water": {"child": "wood", "id": "water_wood", "title_key": "SYN_WATER_WOOD"},
}


## 计算五行相克伤害倍率与削罡倍率
static func evaluate_element_matchup(attack_element: String, target_ward_element: String, mastery_ward_mult: float = 1.0) -> Dictionary:
	if attack_element == "" or attack_element == "none" or target_ward_element == "" or target_ward_element == "none":
		return {
			"relation": "neutral",
			"damage_mult": 1.0,
			"ward_break_mult": 1.0 * mastery_ward_mult,
		}
	if str(ELEMENT_COUNTER_MAP.get(attack_element, "")) == target_ward_element:
		return {
			"relation": "counter",
			"damage_mult": 1.25,
			"ward_break_mult": 2.50 * mastery_ward_mult,
		}
	if str(ELEMENT_COUNTER_MAP.get(target_ward_element, "")) == attack_element:
		return {
			"relation": "resisted",
			"damage_mult": 0.80,
			"ward_break_mult": 0.50,
		}
	return {
		"relation": "neutral",
		"damage_mult": 1.0,
		"ward_break_mult": 1.0 * mastery_ward_mult,
	}


## 结算目标身上的 6 秒【五行母印】与相生子技接力
static func resolve_elemental_synergy(
	current_seal_element: String,
	current_seal_timer: float,
	incoming_element: String,
	applies_seal: bool,
	caster_power: float,
	synergy_dmg_mult: float
) -> Dictionary:
	if incoming_element == "" or incoming_element == "none":
		return {
			"triggered": false,
			"new_seal_element": current_seal_element,
			"new_seal_timer": current_seal_timer,
			"synergy_id": "",
			"title_key": "",
			"bonus_damage": 0.0,
			"attunement_gain": 0.0,
		}

	if current_seal_element != "" and current_seal_timer > 0.0 and ELEMENT_SYNERGY_MAP.has(current_seal_element):
		var rule: Dictionary = ELEMENT_SYNERGY_MAP[current_seal_element] as Dictionary
		if str(rule.get("child", "")) == incoming_element:
			var syn_id: String = str(rule.get("id", ""))
			var bonus_dmg: float = caster_power * 1.35 * maxf(1.0, synergy_dmg_mult)
			return {
				"triggered": true,
				"new_seal_element": "",
				"new_seal_timer": 0.0,
				"synergy_id": syn_id,
				"title_key": str(rule.get("title_key", "")),
				"bonus_damage": bonus_dmg,
				"attunement_gain": SYNERGY_ATTUNEMENT_GAIN,
			}

	if applies_seal:
		return {
			"triggered": false,
			"new_seal_element": incoming_element,
			"new_seal_timer": MOTHER_SEAL_DURATION_SEC,
			"synergy_id": "",
			"title_key": "",
			"bonus_damage": 0.0,
			"attunement_gain": 0.0,
		}

	return {
		"triggered": false,
		"new_seal_element": current_seal_element,
		"new_seal_timer": current_seal_timer,
		"synergy_id": "",
		"title_key": "",
		"bonus_damage": 0.0,
		"attunement_gain": 0.0,
	}


## 计算单次伤害、护罡削减与【气机破绽】触发
static func compute_hit_outcome(
	raw_skill_power: float,
	skill_coeff: float,
	attack_element: String,
	base_ward_damage: float,
	crit_pct: float,
	crit_mult: float,
	guaranteed_crit: bool,
	ignore_armor_pct: float,
	mastery_ward_mult: float,
	preemptive_active: bool,
	target_state: Dictionary,
	rng_roll: float
) -> Dictionary:
	var ward_current: float = float(target_state.get("ward_current", 0.0))
	var ward_max: float = float(target_state.get("ward_max", 0.0))
	var ward_element: String = str(target_state.get("ward_element", "none"))
	var stagger_timer: float = float(target_state.get("stagger_timer", 0.0))
	var target_taken_mult: float = float(target_state.get("damage_taken_mult", 1.0))
	var shield_current: float = float(target_state.get("shield_current", 0.0))

	if ignore_armor_pct > 0.0 and target_taken_mult < 1.0:
		target_taken_mult = lerpf(target_taken_mult, 1.0, clampf(ignore_armor_pct, 0.0, 0.8))

	var matchup: Dictionary = evaluate_element_matchup(attack_element, ward_element, mastery_ward_mult)
	var elem_dmg_mult: float = float(matchup.get("damage_mult", 1.0))
	var ward_mult: float = float(matchup.get("ward_break_mult", 1.0))
	if preemptive_active:
		ward_mult *= 1.50
	if guaranteed_crit:
		ward_mult *= 2.00

	var ward_mitigation: float = 1.0
	if ward_max > 0.0 and ward_current > 0.0 and stagger_timer <= 0.0:
		ward_mitigation = 0.75
	elif stagger_timer > 0.0:
		ward_mitigation = 1.35

	var is_crit: bool = guaranteed_crit or (rng_roll < crit_pct)
	var final_crit_mult: float = crit_mult if is_crit else 1.0
	var raw_dmg: float = maxf(1.0, raw_skill_power * skill_coeff * elem_dmg_mult * ward_mitigation * target_taken_mult * final_crit_mult)

	# 护罡削减与破绽判定
	var ward_broken_now: bool = false
	var new_ward: float = ward_current
	if ward_max > 0.0 and ward_current > 0.0 and stagger_timer <= 0.0 and base_ward_damage > 0.0:
		var ward_loss: float = base_ward_damage * ward_mult
		new_ward = maxf(0.0, ward_current - ward_loss)
		if new_ward <= 0.0:
			ward_broken_now = true

	# 护盾吸收
	var absorbed: float = minf(shield_current, raw_dmg)
	var hp_damage: int = maxi(1, int(round(raw_dmg - absorbed))) if raw_dmg > absorbed else 0
	var remaining_shield: float = maxf(0.0, shield_current - absorbed)

	return {
		"hp_damage": hp_damage,
		"absorbed": int(round(absorbed)),
		"remaining_shield": remaining_shield,
		"is_crit": is_crit,
		"element_relation": str(matchup.get("relation", "neutral")),
		"new_ward": new_ward,
		"ward_broken_now": ward_broken_now,
	}


## 更新单个敌人的杀意表（Threat Table）并返回防抖后的当前攻击目标与姓名板杀意色
static func update_threat_and_pick_target(
	threat_table: Dictionary,
	current_target_id: String,
	taunt_target_id: String,
	taunt_timer: float,
	candidates: Array,
	controlled_actor_id: String
) -> Dictionary:
	if taunt_timer > 0.0 and taunt_target_id != "":
		for raw_c: Variant in candidates:
			if raw_c is Dictionary:
				var cd: Dictionary = raw_c as Dictionary
				if str(cd.get("id", "")) == taunt_target_id and bool(cd.get("alive", false)):
					return {
						"target_id": taunt_target_id,
						"nameplate_state": "jade_safe",
						"top_threat": float(threat_table.get(taunt_target_id, 1.0)),
					}

	var alive_map: Dictionary = {}
	for raw_c2: Variant in candidates:
		if raw_c2 is Dictionary:
			var c: Dictionary = raw_c2 as Dictionary
			if bool(c.get("alive", false)):
				alive_map[str(c.get("id", ""))] = c

	if alive_map.is_empty():
		return {"target_id": "", "nameplate_state": "jade_safe", "top_threat": 0.0}

	var chosen_id: String = current_target_id
	if not alive_map.has(chosen_id):
		chosen_id = ""
		var best_init_threat: float = -1.0
		for aid_var: Variant in alive_map.keys():
			var aid: String = str(aid_var)
			var t_val: float = float(threat_table.get(aid, 0.0))
			if t_val > best_init_threat:
				best_init_threat = t_val
				chosen_id = aid

	var current_threat: float = maxf(1.0, float(threat_table.get(chosen_id, 1.0)))
	var challenger_id: String = chosen_id
	var challenger_threat: float = current_threat

	for aid_var2: Variant in alive_map.keys():
		var aid2: String = str(aid_var2)
		if aid2 == chosen_id:
			continue
		var cand: Dictionary = alive_map[aid2] as Dictionary
		var t_cand: float = float(threat_table.get(aid2, 0.0))
		var is_melee: bool = bool(cand.get("is_melee_range", false))
		var ot_ratio: float = MELEE_OT_RATIO if is_melee else RANGED_OT_RATIO
		if t_cand >= current_threat * ot_ratio and t_cand > challenger_threat:
			challenger_threat = t_cand
			challenger_id = aid2

	chosen_id = challenger_id
	var chosen_cand: Dictionary = alive_map[chosen_id] as Dictionary
	var chosen_is_tank: bool = bool(chosen_cand.get("is_tank_role", false))

	# 计算姓名板杀意变色：青玉稳固 / 琥珀预警(90%-109%) / 朱砂OT
	var nameplate_state: String = "jade_safe"
	if not chosen_is_tank and chosen_id == controlled_actor_id:
		nameplate_state = "cinnabar_ot"
	elif not chosen_is_tank:
		nameplate_state = "cinnabar_ot"
	else:
		var max_non_tank_ratio: float = 0.0
		var tank_threat: float = maxf(1.0, float(threat_table.get(chosen_id, 1.0)))
		for aid_var3: Variant in alive_map.keys():
			var aid3: String = str(aid_var3)
			if aid3 == chosen_id:
				continue
			var ratio: float = float(threat_table.get(aid3, 0.0)) / tank_threat
			if ratio > max_non_tank_ratio:
				max_non_tank_ratio = ratio
		if max_non_tank_ratio >= 0.90:
			nameplate_state = "amber_warn"

	return {
		"target_id": chosen_id,
		"nameplate_state": nameplate_state,
		"top_threat": float(threat_table.get(chosen_id, 0.0)),
	}


static func add_damage_threat(
	threat_table: Dictionary,
	actor_id: String,
	actual_damage: int,
	actor_threat_mult: float,
	flat_bonus_threat: float = 0.0
) -> void:
	var prev: float = float(threat_table.get(actor_id, 0.0))
	var delta: float = float(maxi(0, actual_damage)) * maxf(0.1, actor_threat_mult) + flat_bonus_threat
	threat_table[actor_id] = prev + delta


static func add_heal_threat_split(
	enemy_threat_tables: Array,
	healer_id: String,
	effective_heal: int,
	healer_threat_mult: float
) -> void:
	var count: int = enemy_threat_tables.size()
	if count <= 0 or effective_heal <= 0:
		return
	var per_enemy: float = (float(effective_heal) * 0.5 * maxf(0.1, healer_threat_mult)) / float(count)
	for raw_tbl: Variant in enemy_threat_tables:
		if raw_tbl is Dictionary:
			var tbl: Dictionary = raw_tbl as Dictionary
			tbl[healer_id] = float(tbl.get(healer_id, 0.0)) + per_enemy


## 打断判定：琥珀金条可被打断并触发 3 秒破功封脉；暗红锁链条不可常规打断
static func try_interrupt_cast(is_casting: bool, is_interruptible: bool, base_ward_max: float, current_ward: float) -> Dictionary:
	if not is_casting:
		return {"interrupted": false, "reason": "not_casting", "lockout_sec": 0.0, "bonus_ward_damage": 0.0}
	if not is_interruptible:
		return {"interrupted": false, "reason": "uninterruptible_red", "lockout_sec": 0.0, "bonus_ward_damage": 0.0}
	var bonus_ward_dmg: float = maxf(35.0, base_ward_max * 0.22) if current_ward > 0.0 else 0.0
	return {
		"interrupted": true,
		"reason": "success",
		"lockout_sec": INTERRUPT_LOCKOUT_SEC,
		"bonus_ward_damage": bonus_ward_dmg,
	}


## 记录并裁剪最后 5 秒致命伤害环缓冲，供【问道败北复盘卷轴】精准溯源
static func record_damage_event(
	ring_buffer: Array,
	combat_clock_sec: float,
	source_name: String,
	skill_name: String,
	element: String,
	damage: int,
	was_interruptible_cast: bool,
	was_ground_telegraph: bool,
	victim_name: String
) -> void:
	ring_buffer.append({
		"time_sec": combat_clock_sec,
		"source_name": source_name,
		"skill_name": skill_name,
		"element": element,
		"damage": damage,
		"was_interruptible_cast": was_interruptible_cast,
		"was_ground_telegraph": was_ground_telegraph,
		"victim_name": victim_name,
	})
	while ring_buffer.size() > 24:
		ring_buffer.pop_front()


static func build_defeat_recap(ring_buffer: Array, combat_clock_sec: float, current_formation_id: String, unused_pill_count: int, unused_blue_stunt_name: String) -> Dictionary:
	var recent: Array[Dictionary] = []
	var missed_interrupt_skill: String = ""
	var missed_telegraph_skill: String = ""
	for i: int in range(ring_buffer.size() - 1, -1, -1):
		var raw_ev: Variant = ring_buffer[i]
		if not (raw_ev is Dictionary):
			continue
		var ev: Dictionary = raw_ev as Dictionary
		var t: float = float(ev.get("time_sec", 0.0))
		if combat_clock_sec - t <= DEATH_LOG_WINDOW_SEC or recent.size() < 3:
			recent.append(ev)
			if bool(ev.get("was_interruptible_cast", false)) and missed_interrupt_skill == "":
				missed_interrupt_skill = str(ev.get("skill_name", ""))
			if bool(ev.get("was_ground_telegraph", false)) and missed_telegraph_skill == "":
				missed_telegraph_skill = str(ev.get("skill_name", ""))
		if recent.size() >= 5:
			break

	var tip_key: String = "RECAP_TIP_GENERAL"
	var tip_param: String = ""
	if missed_interrupt_skill != "":
		tip_key = "RECAP_TIP_INTERRUPT"
		tip_param = missed_interrupt_skill
	elif missed_telegraph_skill != "":
		tip_key = "RECAP_TIP_DODGE_TELEGRAPH"
		tip_param = missed_telegraph_skill
	elif current_formation_id != "dizai":
		tip_key = "RECAP_TIP_SWITCH_DIZAI"
	elif unused_blue_stunt_name != "":
		tip_key = "RECAP_TIP_USE_STUNT"
		tip_param = unused_blue_stunt_name
	elif unused_pill_count > 0:
		tip_key = "RECAP_TIP_USE_PILL"

	return {
		"fatal_chain": recent,
		"tip_key": tip_key,
		"tip_param": tip_param,
	}
