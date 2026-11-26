class_name StatLedger
extends RefCounted
## 第一层核心规则：45/35/20 三桶属性账本与梦幻五维 × 魔兽四绿字双曲递减公式
## 严格对齐 docs/design/11-progression-and-math.md，纯 RefCounted 无任何场景/UI依赖。

const BASE_CRIT_PCT: float = 0.05
const BASE_CRIT_MULT: float = 1.60
const BASE_GCD_SEC: float = 1.50
const MIN_GCD_SEC: float = 1.00
const MAX_HASTE_PCT: float = 0.35
const MAX_MOVE_SPEED_BONUS_PCT: float = 0.25
const MIN_DAMAGE_TAKEN_MULT: float = 0.30
const BUCKET_C_MAX_MULT: float = 1.28

const EQUIP_SLOTS: Array[String] = ["weapon", "robe", "boots", "pendant", "treasure"]


static func compute_character_sheet(
	char_def: Dictionary,
	realm_def: Dictionary,
	allocated_potential: Dictionary,
	dao_foundation_grade: String,
	equipped_items: Array,
	set_defs: Dictionary,
	talent_bonuses: Dictionary,
	formation_slot_mod: Dictionary,
	formation_counter_mod: Dictionary,
	active_elixir: Dictionary,
	meridian_bruise_stacks: int = 0,
	realm_suppression_steps: int = 0
) -> Dictionary:
	var k_realm: float = maxf(10.0, float(realm_def.get("k_realm", 20.0)))
	var realm_tier_idx: int = int(realm_def.get("sub_realm_total_index", 0))
	var auto_points: int = realm_tier_idx * 5

	var base_five: Dictionary = _as_dict(char_def.get("base_five_stats", {}))
	var foundation_mult: float = 1.0
	var hp_imprint_mult: float = 1.0
	var lifespan_delta: int = 0
	if dao_foundation_grade == "flawless":
		foundation_mult = 1.08
	elif dao_foundation_grade == "cracked":
		hp_imprint_mult = 0.90
		lifespan_delta = -20

	# ==================== 桶 A：修真境界与潜能五维基石（45% 预算池） ====================
	var con: float = (float(base_five.get("con", 6.0)) + float(auto_points) * 0.22 + float(allocated_potential.get("con", 0))) * foundation_mult
	var spi: float = (float(base_five.get("spi", 6.0)) + float(auto_points) * 0.22 + float(allocated_potential.get("spi", 0))) * foundation_mult
	var str_stat: float = (float(base_five.get("str", 6.0)) + float(auto_points) * 0.20 + float(allocated_potential.get("str", 0))) * foundation_mult
	var end_stat: float = (float(base_five.get("end", 6.0)) + float(auto_points) * 0.18 + float(allocated_potential.get("end", 0))) * foundation_mult
	var agi: float = (float(base_five.get("agi", 6.0)) + float(auto_points) * 0.18 + float(allocated_potential.get("agi", 0))) * foundation_mult

	var realm_hp: float = float(realm_def.get("base_hp", 120.0)) + float(char_def.get("hp_offset", 0.0))
	var realm_mp: float = float(realm_def.get("base_mp", 60.0)) + float(char_def.get("mp_offset", 0.0))
	var realm_atk: float = float(realm_def.get("base_power", 14.0)) + float(char_def.get("power_offset", 0.0))
	var realm_def_val: float = float(realm_def.get("base_defense", 16.0)) + float(char_def.get("def_offset", 0.0))
	var lifespan_max: int = maxi(10, int(realm_def.get("lifespan_max", 80)) + lifespan_delta)

	var bucket_a_hp: float = realm_hp + con * 12.0
	var bucket_a_mp: float = realm_mp + spi * 8.0
	var bucket_a_phys_power: float = realm_atk + str_stat * 1.6
	var bucket_a_spell_power: float = realm_atk + spi * 1.5
	var bucket_a_heal_power: float = realm_atk * 0.85 + spi * 0.8
	var bucket_a_defense: float = realm_def_val + end_stat * 2.2
	var bucket_a_ward_break: float = str_stat * 0.8

	# ==================== 桶 B：5 槽装备、套装与四绿字（35% 预算池） ====================
	var equip_hp: float = 0.0
	var equip_mp: float = 0.0
	var equip_phys_power: float = 0.0
	var equip_spell_power: float = 0.0
	var equip_heal_power: float = 0.0
	var equip_defense: float = 0.0
	var crit_rating: float = agi * 1.2 + float(talent_bonuses.get("crit_rating", 0.0))
	var haste_rating: float = float(talent_bonuses.get("haste_rating", 0.0))
	var mastery_rating: float = float(talent_bonuses.get("mastery_rating", 0.0))
	var vers_rating: float = float(talent_bonuses.get("vers_rating", 0.0))
	var equip_move_pct: float = 0.0

	var attack_interval: float = float(char_def.get("default_attack_interval", 1.8))
	var attack_range_px: float = float(char_def.get("default_attack_range_px", 125.0))
	var blue_stunt_ids: Array[String] = []
	var treasure_skill_id: String = str(char_def.get("default_treasure_skill", ""))
	var set_counts: Dictionary = {}

	for raw_item: Variant in equipped_items:
		if not (raw_item is Dictionary):
			continue
		var item: Dictionary = raw_item as Dictionary
		var slot: String = str(item.get("slot", ""))
		var stats: Dictionary = _as_dict(item.get("stats", {}))
		equip_hp += float(stats.get("hp", 0.0))
		equip_mp += float(stats.get("mp", 0.0))
		equip_phys_power += float(stats.get("phys_power", 0.0))
		equip_spell_power += float(stats.get("spell_power", 0.0))
		equip_heal_power += float(stats.get("heal_power", 0.0))
		equip_defense += float(stats.get("defense", 0.0))
		crit_rating += float(stats.get("crit_rating", 0.0))
		haste_rating += float(stats.get("haste_rating", 0.0))
		mastery_rating += float(stats.get("mastery_rating", 0.0))
		vers_rating += float(stats.get("vers_rating", 0.0))
		equip_move_pct += float(stats.get("move_speed_pct", 0.0))

		if slot == "weapon":
			if item.has("attack_interval"):
				attack_interval = maxf(0.8, float(item.get("attack_interval", 1.8)))
			if item.has("attack_range_px"):
				attack_range_px = maxf(90.0, float(item.get("attack_range_px", 125.0)))
		if slot == "treasure" and str(item.get("treasure_skill_id", "")) != "":
			treasure_skill_id = str(item.get("treasure_skill_id", ""))

		var stunt_id: String = str(item.get("blue_stunt_id", ""))
		if stunt_id != "" and not blue_stunt_ids.has(stunt_id):
			blue_stunt_ids.append(stunt_id)

		var set_id: String = str(item.get("set_id", ""))
		if set_id != "":
			set_counts[set_id] = int(set_counts.get(set_id, 0)) + 1

	var active_set_effects: Array[String] = []
	for set_id_key: Variant in set_counts.keys():
		var sid: String = str(set_id_key)
		var count: int = int(set_counts.get(sid, 0))
		var sdef: Dictionary = _as_dict(set_defs.get(sid, {}))
		if count >= 2:
			var b2: Dictionary = _as_dict(sdef.get("bonus_2pc", {}))
			equip_hp += float(b2.get("hp", 0.0))
			equip_phys_power += float(b2.get("phys_power", 0.0))
			equip_spell_power += float(b2.get("spell_power", 0.0))
			equip_heal_power += float(b2.get("heal_power", 0.0))
			crit_rating += float(b2.get("crit_rating", 0.0))
			haste_rating += float(b2.get("haste_rating", 0.0))
			mastery_rating += float(b2.get("mastery_rating", 0.0))
			var eff2: String = str(b2.get("effect_tag", ""))
			if eff2 != "":
				active_set_effects.append(eff2)
		if count >= 3:
			var b3: Dictionary = _as_dict(sdef.get("bonus_3pc", {}))
			equip_hp += float(b3.get("hp", 0.0))
			equip_heal_power += float(b3.get("heal_power", 0.0))
			mastery_rating += float(b3.get("mastery_rating", 0.0))
			var eff3: String = str(b3.get("effect_tag", ""))
			if eff3 != "":
				active_set_effects.append(eff3)

	# 四绿字双曲递减换算
	var crit_pct: float = convert_crit_rating(crit_rating, k_realm) + float(talent_bonuses.get("flat_crit_pct", 0.0))
	var haste_pct: float = clampf(convert_haste_rating(haste_rating, k_realm) + float(talent_bonuses.get("flat_haste_pct", 0.0)), 0.0, MAX_HASTE_PCT)
	var mastery_pct: float = convert_mastery_rating(mastery_rating, k_realm) + float(talent_bonuses.get("flat_mastery_pct", 0.0))
	var vers_pct: float = convert_versatility_rating(vers_rating, k_realm) + float(talent_bonuses.get("flat_vers_pct", 0.0))

	# ==================== 桶 C：奇门阵法、相克与战前灵丹战术乘区（20% 浮动上限） ====================
	var elixir_hp_pct: float = float(active_elixir.get("max_hp_pct", 0.0))
	var elixir_power_pct: float = float(active_elixir.get("power_pct", 0.0))
	var elixir_def_pct: float = float(active_elixir.get("defense_pct", 0.0))

	var form_dmg_mult: float = float(formation_slot_mod.get("damage_mult", 1.0)) * float(formation_counter_mod.get("damage_mult", 1.0))
	var form_heal_mult: float = float(formation_slot_mod.get("heal_mult", 1.0))
	var form_taken_mult: float = float(formation_slot_mod.get("damage_taken_mult", 1.0)) * float(formation_counter_mod.get("damage_taken_mult", 1.0))
	var form_move_mult: float = float(formation_slot_mod.get("move_speed_mult", 1.0))
	var form_threat_mult: float = float(formation_slot_mod.get("threat_mult", 1.0))
	var form_haste_bonus: float = float(formation_slot_mod.get("haste_bonus", 0.0))
	var form_crit_bonus: float = float(formation_slot_mod.get("crit_bonus", 0.0))
	var form_ward_bonus: float = float(formation_slot_mod.get("ward_break_bonus", 0.0))

	var total_tactical_offense_mult: float = minf(BUCKET_C_MAX_MULT, form_dmg_mult * (1.0 + elixir_power_pct) * (1.0 + float(talent_bonuses.get("damage_pct", 0.0))))
	var total_tactical_heal_mult: float = minf(BUCKET_C_MAX_MULT, form_heal_mult * (1.0 + elixir_power_pct * 0.8) * (1.0 + float(talent_bonuses.get("heal_pct", 0.0))))

	crit_pct = clampf(crit_pct + form_crit_bonus, BASE_CRIT_PCT, 0.48)
	haste_pct = clampf(haste_pct + form_haste_bonus, 0.0, MAX_HASTE_PCT)

	# 经脉暗伤（每次重伤脱战复苏 -6% 最大气血，最多叠 3 层，石碑/丹药清除）
	var bruise_mult: float = clampf(1.0 - float(mini(3, maxi(0, meridian_bruise_stacks))) * 0.06, 0.75, 1.0)
	var max_hp: int = maxi(40, int(round((bucket_a_hp + equip_hp + float(talent_bonuses.get("flat_hp", 0.0))) * (1.0 + elixir_hp_pct) * hp_imprint_mult * bruise_mult)))
	var max_mp: int = maxi(20, int(round(bucket_a_mp + equip_mp + float(talent_bonuses.get("flat_mp", 0.0)))))

	var phys_power: float = (bucket_a_phys_power + equip_phys_power + float(talent_bonuses.get("phys_power", 0.0))) * total_tactical_offense_mult
	var spell_power: float = (bucket_a_spell_power + equip_spell_power + float(talent_bonuses.get("spell_power", 0.0))) * total_tactical_offense_mult
	var heal_power: float = (bucket_a_heal_power + equip_heal_power + float(talent_bonuses.get("heal_power", 0.0))) * total_tactical_heal_mult

	var raw_defense: float = (bucket_a_defense + equip_defense + float(talent_bonuses.get("defense", 0.0))) * (1.0 + elixir_def_pct)
	var effective_defense: float = raw_defense * (1.0 + vers_pct)
	var base_mitigation_mult: float = maxf(MIN_DAMAGE_TAKEN_MULT, 100.0 / (100.0 + effective_defense / k_realm))
	var final_damage_taken_mult: float = maxf(MIN_DAMAGE_TAKEN_MULT, base_mitigation_mult * (1.0 - vers_pct * 0.30) * form_taken_mult)

	var suppression_speed_mult: float = 1.0
	if realm_suppression_steps >= 2:
		final_damage_taken_mult *= 1.35
		suppression_speed_mult = 0.85

	var raw_move_bonus: float = agi * 0.0015 + equip_move_pct + float(talent_bonuses.get("move_speed_pct", 0.0))
	var clamped_move_bonus: float = clampf(raw_move_bonus, -0.20, MAX_MOVE_SPEED_BONUS_PCT)
	var base_move_px: float = float(char_def.get("base_move_speed_px", 215.0))
	var move_speed_px: float = maxf(110.0, base_move_px * (1.0 + clamped_move_bonus) * form_move_mult * suppression_speed_mult)

	var actual_gcd: float = maxf(MIN_GCD_SEC, BASE_GCD_SEC / (1.0 + haste_pct))
	var actual_attack_interval: float = maxf(0.65, attack_interval / (1.0 + haste_pct))
	var ward_break_mult: float = (1.0 + mastery_pct * 1.5 + form_ward_bonus + bucket_a_ward_break * 0.005)
	var synergy_dmg_mult: float = 1.0 + mastery_pct * 2.0
	var stance_threat_mult: float = float(talent_bonuses.get("stance_threat_mult", 1.0))

	return {
		"k_realm": k_realm,
		"lifespan_max": lifespan_max,
		"five_stats": {
			"con": int(round(con)),
			"spi": int(round(spi)),
			"str": int(round(str_stat)),
			"end": int(round(end_stat)),
			"agi": int(round(agi)),
		},
		"max_hp": max_hp,
		"max_mp": max_mp,
		"phys_power": phys_power,
		"spell_power": spell_power,
		"heal_power": heal_power,
		"defense": raw_defense,
		"effective_defense": effective_defense,
		"crit_rating": crit_rating,
		"crit_pct": crit_pct,
		"crit_mult": BASE_CRIT_MULT,
		"haste_rating": haste_rating,
		"haste_pct": haste_pct,
		"mastery_rating": mastery_rating,
		"mastery_pct": mastery_pct,
		"vers_rating": vers_rating,
		"vers_pct": vers_pct,
		"gcd_sec": actual_gcd,
		"attack_interval": actual_attack_interval,
		"attack_range_px": attack_range_px,
		"move_speed_px": move_speed_px,
		"damage_taken_mult": final_damage_taken_mult,
		"mitigation_pct": clampf(1.0 - final_damage_taken_mult, 0.0, 0.70),
		"ward_break_mult": ward_break_mult,
		"synergy_dmg_mult": synergy_dmg_mult,
		"threat_mult": form_threat_mult * stance_threat_mult,
		"ooc_hp_regen_per_sec": 4.0 + con * 0.65,
		"ooc_mp_regen_per_sec": 3.5 + spi * 0.55,
		"initiative": agi * 1.0,
		"blue_stunt_ids": blue_stunt_ids,
		"treasure_skill_id": treasure_skill_id,
		"active_set_effects": active_set_effects,
		"set_counts": set_counts,
		"bucket_breakdown": {
			"bucket_a_hp": int(round(bucket_a_hp)),
			"bucket_b_hp": int(round(equip_hp)),
			"bucket_c_offense_mult": total_tactical_offense_mult,
		}
	}


static func convert_crit_rating(rating: float, k_realm: float) -> float:
	var r: float = maxf(0.0, rating)
	var denom: float = r + 3.2 * maxf(1.0, k_realm)
	return BASE_CRIT_PCT + (r / denom) * 0.45


static func convert_haste_rating(rating: float, k_realm: float) -> float:
	var r: float = maxf(0.0, rating)
	var denom: float = r + 3.0 * maxf(1.0, k_realm)
	return minf(MAX_HASTE_PCT, (r / denom) * 0.42)


static func convert_mastery_rating(rating: float, k_realm: float) -> float:
	var r: float = maxf(0.0, rating)
	var denom: float = r + 3.0 * maxf(1.0, k_realm)
	return (r / denom) * 0.40


static func convert_versatility_rating(rating: float, k_realm: float) -> float:
	var r: float = maxf(0.0, rating)
	var denom: float = r + 3.5 * maxf(1.0, k_realm)
	return (r / denom) * 0.35


static func compute_actual_cast_time(base_cast_sec: float, haste_pct: float) -> float:
	if base_cast_sec <= 0.0:
		return 0.0
	return maxf(0.35, base_cast_sec / (1.0 + clampf(haste_pct, 0.0, MAX_HASTE_PCT)))


static func evaluate_breakthrough_grade(
	has_main_pill: bool,
	has_aux_charm: bool,
	protector_bond_tier: int,
	trial_victory: bool,
	used_protector_save: bool
) -> Dictionary:
	if not trial_victory:
		return {
			"success": false,
			"grade": "failed",
			"lifespan_cost": 0,
			"title_key": "UI_BREAKTHROUGH_FAIL",
		}
	if not has_main_pill:
		return {
			"success": true,
			"grade": "cracked",
			"lifespan_cost": 20,
			"title_key": "UI_BREAKTHROUGH_CRACKED",
		}
	if has_aux_charm and protector_bond_tier >= 2 and not used_protector_save:
		return {
			"success": true,
			"grade": "flawless",
			"lifespan_cost": 0,
			"title_key": "UI_BREAKTHROUGH_FLAWLESS",
		}
	return {
		"success": true,
		"grade": "solid",
		"lifespan_cost": 0,
		"title_key": "UI_BREAKTHROUGH_SOLID",
	}


static func _as_dict(val: Variant) -> Dictionary:
	if val is Dictionary:
		return val as Dictionary
	return {}
