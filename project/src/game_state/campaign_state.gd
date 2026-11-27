extends Node
## 第二层状态服务单例（4/5）：战役全局状态树（CampaignState）
## 管理当前队伍、五维潜能、双专精、5槽装备、唯一货币【灵石】、行囊、【断玉剑匣】提纯槽、
## 奇门阵位、初生灵宠、引灵石碑、声望、同伴五阶羁绊、《问道手札》与因果水墨签。
## 包含 scene_epoch 纪元守卫与 sandbox_mode 物理隔离标记。

signal party_updated()
signal inventory_updated()
signal spirit_stones_changed(new_amount: int)
signal formation_changed(formation_id: String)
signal sword_box_updated()
signal journal_updated()

const BOND_TIER_KEYS: Array[String] = [
	"BOND_TIER_1",
	"BOND_TIER_2",
	"BOND_TIER_3",
	"BOND_TIER_4",
	"BOND_TIER_5",
]

var scene_epoch: int = 1
var sandbox_mode: bool = false

var difficulty: String = "cultivation" # ask_heart / cultivation / tribulation
var chapter_id: String = "ch01_qinglan"
var current_zone_id: String = "tingyu_town"
var current_spawn_tag: String = "town_south_entry"
var saved_player_pos: Vector2 = Vector2(360.0, 620.0)
var playtime_sec: float = 0.0

var spirit_stones: int = 120
var active_formation_id: String = "scatter"
var unlocked_formations: Array[String] = ["scatter"]
var formation_slots: Array[String] = ["gu_changqing", "", "", ""]

## 角色运行时状态表 char_id -> Dictionary
var party_members: Dictionary = {}
var recruited_order: Array[String] = ["gu_changqing"]
var controlled_slot: int = 1

## 初生灵宠状态（山道救护奇遇二选一：pet_fire_fox / pet_spirit_turtle）
var active_pet_id: String = ""
var unlocked_pets: Array[String] = []
var pet_stance: String = "assist" # assist / follow / hold
var pet_hp_ratio: float = 1.0

## 行囊与快捷丹药槽（5/6 键）
var inventory: Array[Dictionary] = []
var quick_pill_5_id: String = "item_huichun_powder"
var quick_pill_6_id: String = "item_qingmu_pill"
var active_elixir: Dictionary = {} # {item_id, remaining_sec, power_pct, max_hp_pct, defense_pct}

## 炼丹与【断玉剑匣】提纯槽
var unlocked_recipes: Array[String] = ["recipe_huichun_powder"]
var quick_brew_recipes: Array[String] = []
var sword_box_unlocked: bool = true
var sword_box_slot: Dictionary = {} # {input_item_id, output_item_id, output_count, battles_remaining}

## 叙事、手札、石碑与世界状态
var unlocked_steles: Array[String] = []
var last_rested_stele_id: String = "stele_tingyu_gate"
var quest_states: Dictionary = {}
var unlocked_clues: Array[String] = []
var companion_bonds: Dictionary = {"shen_qinghe": 1, "pei_zhao": 1}
var dao_heart_weights: Dictionary = {"lone_peak": 0, "mortal_mercy": 0, "seek_truth": 0}
var ink_seals: Array[String] = []
var faction_reputation: Dictionary = {
	"qingyun_sect": 0,
	"jishi_pharmacy": 200,
	"zhaoying_keepers": 0,
	"chiyuan_league": 0,
	"jianxu_forge": 0,
}
var unlocked_cgs: Array[String] = []
var unlocked_bond_ultimates: Array[String] = []
var viewed_night_talks: Array[String] = []
var read_dialogues: Dictionary = {}
var world_flags: Dictionary = {}
var cleared_encounters: Dictionary = {}
var opened_containers: Dictionary = {}


func _process(delta: float) -> void:
	playtime_sec += delta
	if not active_elixir.is_empty():
		var rem: float = float(active_elixir.get("remaining_sec", 0.0)) - delta
		if rem <= 0.0:
			active_elixir.clear()
			party_updated.emit()
		else:
			active_elixir["remaining_sec"] = rem


func bump_scene_epoch() -> int:
	scene_epoch += 1
	return scene_epoch


func start_new_campaign(selected_difficulty: String = "cultivation") -> void:
	DataDB.load_all()
	bump_scene_epoch()
	sandbox_mode = false
	difficulty = selected_difficulty
	chapter_id = "ch01_qinglan"
	current_zone_id = "tingyu_town"
	current_spawn_tag = "town_south_entry"
	saved_player_pos = Vector2(360.0, 640.0)
	playtime_sec = 0.0

	spirit_stones = 135
	active_formation_id = "scatter"
	unlocked_formations = ["scatter"]
	formation_slots = ["gu_changqing", "", "", ""]
	recruited_order = ["gu_changqing"]
	controlled_slot = 1

	party_members.clear()
	_init_member_state("gu_changqing", "mortal", true)
	_init_member_state("shen_qinghe", "qi_refining_1", false)
	_init_member_state("pei_zhao", "qi_refining_2", false)

	active_pet_id = ""
	unlocked_pets = []
	pet_stance = "assist"
	pet_hp_ratio = 1.0

	inventory = [
		{"id": "item_huichun_powder", "count": 3},
		{"id": "item_ningqi_herb", "count": 3},
		{"id": "item_qingmu_leaf", "count": 2},
		{"id": "item_stealth_talisman", "count": 2},
	]
	quick_pill_5_id = "item_huichun_powder"
	quick_pill_6_id = "item_stealth_talisman"
	active_elixir = {}

	unlocked_recipes = ["recipe_huichun_powder", "recipe_juqi_pellet"]
	quick_brew_recipes = []
	sword_box_unlocked = true
	sword_box_slot = {}

	unlocked_steles = ["stele_tingyu_gate"]
	last_rested_stele_id = "stele_tingyu_gate"
	quest_states = {
		"q_main_ch01": "stage_seek_medicine",
		"q_side_yaolu_spy": "inactive",
		"q_side_spirit_pet": "inactive",
	}
	unlocked_clues = ["clue_tingyu_miasma", "clue_sword_box_secret"]
	companion_bonds = {"shen_qinghe": 1, "pei_zhao": 1}
	dao_heart_weights = {"lone_peak": 0, "mortal_mercy": 0, "seek_truth": 0}
	ink_seals = []
	faction_reputation = {
		"qingyun_sect": 0,
		"jishi_pharmacy": 200,
		"zhaoying_keepers": 0,
		"chiyuan_league": 0,
		"jianxu_forge": 0,
	}
	unlocked_cgs = []
	unlocked_bond_ultimates = []
	viewed_night_talks = []
	read_dialogues = {}
	world_flags = {
		"met_shen_qinghe": false,
		"temple_cg_played": false,
		"met_pei_zhao": false,
		"peddler_gem_bought": false,
		"rogue_ambush_cleared": false,
		"yaolu_spy_resolved": false,
		"vine_wall_burned": false,
		"miasma_pool_cleansed": false,
		"shortcut_gate_opened": false,
		"wolf_king_defeated": false,
		"marrow_choice": "",
		"ch01_completed": false,
	}
	cleared_encounters = {}
	opened_containers = {}

	recalculate_all_party_stats(true)
	party_updated.emit()
	inventory_updated.emit()
	journal_updated.emit()


func _init_member_state(char_id: String, initial_realm: String, recruited: bool) -> void:
	var cdef: Dictionary = DataDB.get_character(char_id)
	var default_equips: Dictionary = {}
	var raw_eq: Variant = cdef.get("starter_equipment", {})
	if raw_eq is Dictionary:
		var eq_dict: Dictionary = raw_eq as Dictionary
		for slot_name: String in StatLedger.EQUIP_SLOTS:
			default_equips[slot_name] = str(eq_dict.get(slot_name, ""))
	var realm_def: Dictionary = DataDB.get_realm(initial_realm)
	var free_pts: int = int(realm_def.get("sub_realm_total_index", 0)) * 5
	party_members[char_id] = {
		"id": char_id,
		"recruited": recruited,
		"realm_id": initial_realm,
		"dao_foundation_grade": "solid",
		"free_potential": free_pts,
		"allocated_potential": {"con": 0, "spi": 0, "str": 0, "end": 0, "agi": 0},
		"active_spec": "spec_a",
		"unlocked_talents": _get_default_talents(cdef, "spec_a"),
		"equipped": default_equips,
		"meridian_bruise": 0,
		"ai_preset_index": 0,
		"hp": 120,
		"mp": 60,
		"sheet": {},
	}


func _get_default_talents(cdef: Dictionary, spec_key: String) -> Array[String]:
	var out: Array[String] = []
	var specs: Dictionary = cdef.get("specializations", {}) as Dictionary
	var sp: Dictionary = specs.get(spec_key, {}) as Dictionary
	var nodes: Array = sp.get("nodes", []) as Array
	if not nodes.is_empty() and nodes[0] is Dictionary:
		out.append(str((nodes[0] as Dictionary).get("id", "")))
	return out


func recruit_companion(char_id: String, preferred_slot: int = 2) -> void:
	if not party_members.has(char_id):
		return
	var m: Dictionary = party_members[char_id] as Dictionary
	m["recruited"] = true
	if not recruited_order.has(char_id):
		recruited_order.append(char_id)
	var already_slotted: bool = false
	for s: String in formation_slots:
		if s == char_id:
			already_slotted = true
	if not already_slotted:
		var idx: int = clampi(preferred_slot - 1, 0, 3)
		if formation_slots[idx] == "":
			formation_slots[idx] = char_id
		elif char_id == "pei_zhao" and idx == 1 and formation_slots[2] == "":
			# 裴照入阵接掌 2 号玄武前锋位，原 2 号位沈清禾顺移至 3 号朱雀灵枢位，保持 F1-F2-F3 连续且职责契合！
			formation_slots[2] = formation_slots[1]
			formation_slots[1] = char_id
			if controlled_slot == 2:
				controlled_slot = 3
		else:
			for i: int in range(4):
				if formation_slots[i] == "":
					formation_slots[i] = char_id
					break
	recalculate_all_party_stats(true)
	party_updated.emit()


func unlock_formation(formation_id: String, auto_equip: bool = false) -> void:
	if not unlocked_formations.has(formation_id):
		unlocked_formations.append(formation_id)
		var fdef: Dictionary = DataDB.get_formation(formation_id)
		NotifyHub.push_explore_slip(tr("NOTIFY_FORMATION_UNLOCKED"), DataDB.loc(str(fdef.get("name_key", formation_id))), "unlock")
	if auto_equip:
		set_active_formation(formation_id)


func set_active_formation(formation_id: String) -> void:
	if not unlocked_formations.has(formation_id):
		return
	active_formation_id = formation_id
	recalculate_all_party_stats(false)
	formation_changed.emit(formation_id)
	party_updated.emit()


func swap_formation_slots(slot_a: int, slot_b: int) -> void:
	var ia: int = clampi(slot_a - 1, 0, 3)
	var ib: int = clampi(slot_b - 1, 0, 3)
	if ia == ib:
		return
	var tmp: String = formation_slots[ia]
	formation_slots[ia] = formation_slots[ib]
	formation_slots[ib] = tmp
	recalculate_all_party_stats(false)
	party_updated.emit()


func contract_spirit_pet(pet_id: String) -> void:
	if not unlocked_pets.has(pet_id):
		unlocked_pets.append(pet_id)
	active_pet_id = pet_id
	pet_hp_ratio = 1.0
	var pdef: Dictionary = DataDB.get_pet(pet_id)
	NotifyHub.push_explore_slip(tr("NOTIFY_PET_CONTRACTED"), DataDB.loc(str(pdef.get("name_key", pet_id))), "pet")
	party_updated.emit()


func get_difficulty_enemy_damage_mult() -> float:
	if difficulty == "ask_heart":
		return 0.72
	if difficulty == "tribulation":
		return 1.25
	return 1.00


func get_difficulty_enemy_hp_mult() -> float:
	if difficulty == "ask_heart":
		return 0.82
	if difficulty == "tribulation":
		return 1.20
	return 1.00


func recalculate_all_party_stats(full_restore: bool = false) -> void:
	var form_def: Dictionary = DataDB.get_formation(active_formation_id)
	for char_id_var: Variant in party_members.keys():
		var cid: String = str(char_id_var)
		var m: Dictionary = party_members[cid] as Dictionary
		var cdef: Dictionary = DataDB.get_character(cid)
		var rdef: Dictionary = DataDB.get_realm(str(m.get("realm_id", "mortal")))
		var slot_idx: int = get_member_formation_slot(cid)
		var slot_mod: Dictionary = FormationRules.get_slot_modifiers(form_def, slot_idx)
		var eq_list: Array = []
		var eq_map: Dictionary = m.get("equipped", {}) as Dictionary
		for sname: String in StatLedger.EQUIP_SLOTS:
			var eq_id: String = str(eq_map.get(sname, ""))
			if eq_id != "":
				var edef: Dictionary = DataDB.get_equipment(eq_id)
				if not edef.is_empty():
					eq_list.append(edef)
		var talent_bonuses: Dictionary = _gather_talent_bonuses(cdef, str(m.get("active_spec", "spec_a")), m.get("unlocked_talents", []) as Array)
		if cid == "gu_changqing" and str(world_flags.get("marrow_choice", "")) == "absorb":
			talent_bonuses["damage_pct"] = float(talent_bonuses.get("damage_pct", 0.0)) + 0.08
			talent_bonuses["flat_mastery_pct"] = float(talent_bonuses.get("flat_mastery_pct", 0.0)) + 0.05

		var sheet: Dictionary = StatLedger.compute_character_sheet(
			cdef,
			rdef,
			m.get("allocated_potential", {}) as Dictionary,
			str(m.get("dao_foundation_grade", "solid")),
			eq_list,
			DataDB.equip_sets,
			talent_bonuses,
			slot_mod,
			{"damage_mult": 1.0, "damage_taken_mult": 1.0},
			active_elixir,
			int(m.get("meridian_bruise", 0)),
			0
		)
		m["sheet"] = sheet
		var max_hp: int = int(sheet.get("max_hp", 120))
		var max_mp: int = int(sheet.get("max_mp", 60))
		if full_restore:
			m["hp"] = max_hp
			m["mp"] = max_mp
		else:
			m["hp"] = clampi(int(m.get("hp", max_hp)), 1, max_hp)
			m["mp"] = clampi(int(m.get("mp", max_mp)), 0, max_mp)


func _gather_talent_bonuses(cdef: Dictionary, spec_key: String, unlocked_nodes: Array) -> Dictionary:
	var totals: Dictionary = {}
	var specs: Dictionary = cdef.get("specializations", {}) as Dictionary
	var sp: Dictionary = specs.get(spec_key, {}) as Dictionary
	var nodes: Array = sp.get("nodes", []) as Array
	for raw_n: Variant in nodes:
		if not (raw_n is Dictionary):
			continue
		var nd: Dictionary = raw_n as Dictionary
		var nid: String = str(nd.get("id", ""))
		var has_it: bool = false
		for u_var: Variant in unlocked_nodes:
			if str(u_var) == nid:
				has_it = true
				break
		if has_it:
			var bonuses: Dictionary = nd.get("bonuses", {}) as Dictionary
			for bk_var: Variant in bonuses.keys():
				var bk: String = str(bk_var)
				totals[bk] = float(totals.get(bk, 0.0)) + float(bonuses[bk])
	return totals


func get_member_formation_slot(char_id: String) -> int:
	for i: int in range(formation_slots.size()):
		if formation_slots[i] == char_id:
			return i + 1
	return 1


func get_active_party_ids() -> Array[String]:
	var result: Array[String] = []
	for s: String in formation_slots:
		if s != "" and party_members.has(s):
			var m: Dictionary = party_members[s] as Dictionary
			if bool(m.get("recruited", false)):
				result.append(s)
	return result


func get_member_active_skills(char_id: String) -> Dictionary:
	var m: Dictionary = party_members.get(char_id, {}) as Dictionary
	var cdef: Dictionary = DataDB.get_character(char_id)
	var spec_key: String = str(m.get("active_spec", "spec_a"))
	var specs: Dictionary = cdef.get("specializations", {}) as Dictionary
	var sp: Dictionary = specs.get(spec_key, {}) as Dictionary
	var bar: Dictionary = (sp.get("skill_bar", {}) as Dictionary).duplicate()
	var sheet: Dictionary = m.get("sheet", {}) as Dictionary
	var treasure_skill: String = str(sheet.get("treasure_skill_id", ""))
	if treasure_skill != "":
		bar["R"] = treasure_skill
	return bar


func allocate_potential_point(char_id: String, stat_key: String, delta_pts: int = 1) -> bool:
	if not party_members.has(char_id):
		return false
	var m: Dictionary = party_members[char_id] as Dictionary
	var free_pts: int = int(m.get("free_potential", 0))
	if delta_pts <= 0 or free_pts < delta_pts:
		return false
	var alloc: Dictionary = m.get("allocated_potential", {}) as Dictionary
	if not alloc.has(stat_key):
		return false
	alloc[stat_key] = int(alloc.get(stat_key, 0)) + delta_pts
	m["free_potential"] = free_pts - delta_pts
	recalculate_all_party_stats(false)
	party_updated.emit()
	return true


func reset_potential_points(char_id: String) -> bool:
	if not party_members.has(char_id):
		return false
	if get_item_count("item_marrow_dew") <= 0:
		return false
	var m: Dictionary = party_members[char_id] as Dictionary
	var alloc: Dictionary = m.get("allocated_potential", {}) as Dictionary
	var refunded: int = 0
	for k_var: Variant in alloc.keys():
		var k: String = str(k_var)
		refunded += int(alloc[k])
		alloc[k] = 0
	if refunded <= 0:
		return false
	remove_item("item_marrow_dew", 1)
	m["free_potential"] = int(m.get("free_potential", 0)) + refunded
	recalculate_all_party_stats(false)
	party_updated.emit()
	return true


func switch_specialization(char_id: String, new_spec_key: String) -> bool:
	if NotifyHub.combat_active or not party_members.has(char_id):
		return false
	var m: Dictionary = party_members[char_id] as Dictionary
	var cdef: Dictionary = DataDB.get_character(char_id)
	var specs: Dictionary = cdef.get("specializations", {}) as Dictionary
	if not specs.has(new_spec_key):
		return false
	m["active_spec"] = new_spec_key
	var rdef: Dictionary = DataDB.get_realm(str(m.get("realm_id", "mortal")))
	var max_tier: int = clampi(int(rdef.get("sub_realm_total_index", 0)) + 1, 1, 3)
	var sp: Dictionary = specs[new_spec_key] as Dictionary
	var nodes: Array = sp.get("nodes", []) as Array
	var unlocked: Array[String] = []
	for i: int in range(mini(max_tier, nodes.size())):
		if nodes[i] is Dictionary:
			unlocked.append(str((nodes[i] as Dictionary).get("id", "")))
	m["unlocked_talents"] = unlocked
	recalculate_all_party_stats(false)
	party_updated.emit()
	return true


func equip_item_on_member(char_id: String, equip_id: String) -> bool:
	if NotifyHub.combat_active or not party_members.has(char_id):
		return false
	if get_item_count(equip_id) <= 0:
		return false
	var edef: Dictionary = DataDB.get_equipment(equip_id)
	if edef.is_empty():
		return false
	var slot: String = str(edef.get("slot", ""))
	if not StatLedger.EQUIP_SLOTS.has(slot):
		return false
	var allowed_chars: Array = edef.get("allowed_characters", []) as Array
	if not allowed_chars.is_empty() and not allowed_chars.has(char_id):
		return false

	var m: Dictionary = party_members[char_id] as Dictionary
	var eq_map: Dictionary = m.get("equipped", {}) as Dictionary
	var prev_id: String = str(eq_map.get(slot, ""))
	remove_item(equip_id, 1)
	if prev_id != "":
		add_item(prev_id, 1, true)
	eq_map[slot] = equip_id
	recalculate_all_party_stats(false)
	party_updated.emit()
	inventory_updated.emit()
	return true


func advance_member_realm(char_id: String, target_realm_id: String, grade: String = "solid") -> void:
	if not party_members.has(char_id):
		return
	var m: Dictionary = party_members[char_id] as Dictionary
	var old_rdef: Dictionary = DataDB.get_realm(str(m.get("realm_id", "mortal")))
	var new_rdef: Dictionary = DataDB.get_realm(target_realm_id)
	if new_rdef.is_empty():
		return
	var diff_idx: int = maxi(0, int(new_rdef.get("sub_realm_total_index", 0)) - int(old_rdef.get("sub_realm_total_index", 0)))
	m["realm_id"] = target_realm_id
	m["dao_foundation_grade"] = grade
	m["free_potential"] = int(m.get("free_potential", 0)) + diff_idx * 5
	# 自动激活对应层数专精节点
	switch_specialization(char_id, str(m.get("active_spec", "spec_a")))
	recalculate_all_party_stats(true)
	party_updated.emit()


func get_item_count(item_id: String) -> int:
	for entry: Dictionary in inventory:
		if str(entry.get("id", "")) == item_id:
			return int(entry.get("count", 0))
	return 0


func add_item(item_id: String, count: int = 1, silent: bool = false) -> void:
	if item_id == "" or count <= 0:
		return
	var found: bool = false
	for entry: Dictionary in inventory:
		if str(entry.get("id", "")) == item_id:
			entry["count"] = int(entry.get("count", 0)) + count
			found = true
			break
	if not found:
		inventory.append({"id": item_id, "count": count})
	if not silent:
		var idef: Dictionary = DataDB.get_any_item_or_equip(item_id)
		var iname: String = DataDB.loc(str(idef.get("name_key", item_id)))
		NotifyHub.push_explore_slip(tr("NOTIFY_ITEM_GAINED"), "%s ×%d" % [iname, count], "loot")
	inventory_updated.emit()


func remove_item(item_id: String, count: int = 1) -> bool:
	if item_id == "" or count <= 0:
		return false
	for i: int in range(inventory.size()):
		var entry: Dictionary = inventory[i]
		if str(entry.get("id", "")) == item_id:
			var cur: int = int(entry.get("count", 0))
			if cur < count:
				return false
			if cur == count:
				inventory.remove_at(i)
			else:
				entry["count"] = cur - count
			inventory_updated.emit()
			return true
	return false


func sort_inventory_by_grade() -> void:
	var grade_rank: Dictionary = {
		"immortal": 6,
		"heaven": 5,
		"earth": 4,
		"mystic": 3,
		"spirit": 2,
		"mortal": 1,
	}
	inventory.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da: Dictionary = DataDB.get_any_item_or_equip(str(a.get("id", "")))
		var db: Dictionary = DataDB.get_any_item_or_equip(str(b.get("id", "")))
		var ga: int = int(grade_rank.get(str(da.get("grade", "mortal")), 1))
		var gb: int = int(grade_rank.get(str(db.get("grade", "mortal")), 1))
		if ga != gb:
			return ga > gb
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	inventory_updated.emit()


func add_spirit_stones(delta: int, silent: bool = false) -> bool:
	if delta < 0 and spirit_stones + delta < 0:
		return false
	spirit_stones += delta
	if delta > 0 and not silent:
		NotifyHub.push_explore_slip(tr("NOTIFY_STONES_GAINED"), "+%d %s" % [delta, tr("TERM_SPIRIT_STONE")], "stone")
	spirit_stones_changed.emit(spirit_stones)
	return true


func use_out_of_combat_item(item_id: String) -> Dictionary:
	if get_item_count(item_id) <= 0:
		return {"ok": false, "msg": tr("MSG_NO_ITEM")}
	var idef: Dictionary = DataDB.get_any_item_or_equip(item_id)
	var category: String = str(idef.get("category", ""))
	if category == "elixir":
		remove_item(item_id, 1)
		active_elixir = {
			"item_id": item_id,
			"remaining_sec": float(idef.get("duration_sec", 1800.0)),
			"power_pct": float(idef.get("power_pct", 0.0)),
			"max_hp_pct": float(idef.get("max_hp_pct", 0.0)),
			"defense_pct": float(idef.get("defense_pct", 0.0)),
		}
		recalculate_all_party_stats(false)
		party_updated.emit()
		return {"ok": true, "msg": DataDB.loc(str(idef.get("name_key", item_id)))}
	elif category == "instant_pill":
		remove_item(item_id, 1)
		var heal_pct: float = float(idef.get("heal_hp_pct", 0.35))
		var cleanse_bruise: bool = bool(idef.get("cleanse_meridian_bruise", false))
		for cid: String in get_active_party_ids():
			var m: Dictionary = party_members[cid] as Dictionary
			if cleanse_bruise:
				m["meridian_bruise"] = 0
		recalculate_all_party_stats(false)
		for cid2: String in get_active_party_ids():
			var m2: Dictionary = party_members[cid2] as Dictionary
			var max_hp: int = int((m2.get("sheet", {}) as Dictionary).get("max_hp", 120))
			m2["hp"] = mini(max_hp, int(m2.get("hp", max_hp)) + int(round(float(max_hp) * heal_pct)))
		party_updated.emit()
		return {"ok": true, "msg": DataDB.loc(str(idef.get("name_key", item_id)))}
	elif category == "storage_pouch":
		remove_item(item_id, 1)
		var loot_stones: int = int(idef.get("grant_stones", 95))
		add_spirit_stones(loot_stones, false)
		var loot_items: Array = idef.get("grant_items", []) as Array
		for raw_li: Variant in loot_items:
			if raw_li is Dictionary:
				var li: Dictionary = raw_li as Dictionary
				add_item(str(li.get("id", "")), int(li.get("count", 1)), false)
		var grant_clue: String = str(idef.get("grant_clue", ""))
		if grant_clue != "":
			unlock_clue(grant_clue)
		var grant_recipe: String = str(idef.get("grant_recipe", ""))
		if grant_recipe != "" and not unlocked_recipes.has(grant_recipe):
			unlocked_recipes.append(grant_recipe)
		return {"ok": true, "msg": tr("MSG_POUCH_OPENED")}
	return {"ok": false, "msg": tr("MSG_CANNOT_USE_HERE")}


## 【断玉剑匣 · 混元提纯】装填与推进
func start_sword_box_purify(item_id: String) -> bool:
	if not sword_box_unlocked or not sword_box_slot.is_empty():
		return false
	if get_item_count(item_id) <= 0:
		return false
	var idef: Dictionary = DataDB.get_any_item_or_equip(item_id)
	var rule: Dictionary = EconomyRules.resolve_sword_box_purification(idef)
	if not bool(rule.get("can_purify", false)):
		return false
	remove_item(item_id, 1)
	sword_box_slot = {
		"input_item_id": item_id,
		"output_item_id": str(rule.get("output_item_id", "")),
		"output_count": int(rule.get("output_count", 1)),
		"battles_remaining": int(rule.get("required_battles", 3)),
	}
	sword_box_updated.emit()
	return true


func advance_sword_box_progress(steps: int = 1) -> void:
	if sword_box_slot.is_empty():
		return
	var rem: int = maxi(0, int(sword_box_slot.get("battles_remaining", 0)) - steps)
	sword_box_slot["battles_remaining"] = rem
	if rem == 0:
		NotifyHub.push_explore_slip(tr("NOTIFY_SWORD_BOX_READY"), tr("NOTIFY_SWORD_BOX_READY_DESC"), "sword_box")
	sword_box_updated.emit()


func claim_sword_box_output() -> bool:
	if sword_box_slot.is_empty():
		return false
	if int(sword_box_slot.get("battles_remaining", 1)) > 0:
		return false
	var out_id: String = str(sword_box_slot.get("output_item_id", ""))
	var out_cnt: int = maxi(1, int(sword_box_slot.get("output_count", 1)))
	sword_box_slot.clear()
	add_item(out_id, out_cnt, false)
	sword_box_updated.emit()
	return true


func rest_at_stele(stele_id: String) -> void:
	if stele_id != "" and not unlocked_steles.has(stele_id):
		unlocked_steles.append(stele_id)
	if stele_id != "":
		last_rested_stele_id = stele_id
	for cid_var: Variant in party_members.keys():
		var m: Dictionary = party_members[str(cid_var)] as Dictionary
		m["meridian_bruise"] = 0
	pet_hp_ratio = 1.0
	recalculate_all_party_stats(true)
	advance_sword_box_progress(3)
	party_updated.emit()


func unlock_clue(clue_id: String) -> void:
	if clue_id == "" or unlocked_clues.has(clue_id):
		return
	unlocked_clues.append(clue_id)
	var jdef: Dictionary = DataDB.journal_entries.get(clue_id, {}) as Dictionary
	var title_txt: String = DataDB.loc(str(jdef.get("title_key", clue_id)))
	NotifyHub.push_explore_slip(tr("NOTIFY_JOURNAL_UPDATED"), title_txt, "journal")
	journal_updated.emit()


func add_companion_bond(char_id: String, delta_tier: int = 1) -> void:
	var cur: int = int(companion_bonds.get(char_id, 1))
	var next_tier: int = clampi(cur + delta_tier, 1, 5)
	if next_tier == cur:
		return
	companion_bonds[char_id] = next_tier
	var cdef: Dictionary = DataDB.get_character(char_id)
	var cname: String = DataDB.loc(str(cdef.get("name_key", char_id)))
	var tier_label: String = tr(BOND_TIER_KEYS[next_tier - 1])
	NotifyHub.push_explore_slip(tr("NOTIFY_BOND_UP"), "%s · %s" % [cname, tier_label], "bond")
	if char_id == "shen_qinghe" and next_tier >= 2 and not unlocked_bond_ultimates.has("ult_qinglian_sword"):
		unlocked_bond_ultimates.append("ult_qinglian_sword")
		NotifyHub.push_explore_slip(tr("NOTIFY_BOND_ULT_UNLOCKED"), tr("SKILL_NAME_ULT_QINGLIAN"), "unlock")
	journal_updated.emit()


func add_faction_reputation(faction_id: String, delta_rep: int) -> void:
	if delta_rep == 0 or not faction_reputation.has(faction_id):
		return
	faction_reputation[faction_id] = maxi(0, int(faction_reputation.get(faction_id, 0)) + delta_rep)
	var fdef: Dictionary = DataDB.factions.get(faction_id, {}) as Dictionary
	var fname: String = DataDB.loc(str(fdef.get("name_key", faction_id)))
	NotifyHub.push_explore_slip(tr("NOTIFY_REP_GAINED"), "%s +%d" % [fname, delta_rep], "rep")
	journal_updated.emit()


func stamp_ink_seal(seal_id: String, axis_key: String = "") -> void:
	if axis_key != "" and dao_heart_weights.has(axis_key):
		dao_heart_weights[axis_key] = int(dao_heart_weights.get(axis_key, 0)) + 1
	if seal_id != "" and not ink_seals.has(seal_id):
		ink_seals.append(seal_id)
		var sdef: Dictionary = DataDB.ink_seals.get(seal_id, {}) as Dictionary
		NotifyHub.push_explore_slip(tr("NOTIFY_INK_SEAL"), DataDB.loc(str(sdef.get("name_key", seal_id))), "seal")
	journal_updated.emit()


func serialize_payload() -> Dictionary:
	return {
		"difficulty": difficulty,
		"chapter_id": chapter_id,
		"current_zone_id": current_zone_id,
		"current_spawn_tag": current_spawn_tag,
		"saved_player_pos": {"x": snappedf(saved_player_pos.x, 0.1), "y": snappedf(saved_player_pos.y, 0.1)},
		"playtime_sec": snappedf(playtime_sec, 0.1),
		"spirit_stones": spirit_stones,
		"active_formation_id": active_formation_id,
		"unlocked_formations": unlocked_formations.duplicate(),
		"formation_slots": formation_slots.duplicate(),
		"recruited_order": recruited_order.duplicate(),
		"controlled_slot": controlled_slot,
		"party_members": _serialize_party_members(),
		"active_pet_id": active_pet_id,
		"unlocked_pets": unlocked_pets.duplicate(),
		"pet_stance": pet_stance,
		"pet_hp_ratio": snappedf(pet_hp_ratio, 0.01),
		"inventory": inventory.duplicate(true),
		"quick_pill_5_id": quick_pill_5_id,
		"quick_pill_6_id": quick_pill_6_id,
		"active_elixir": active_elixir.duplicate(true),
		"unlocked_recipes": unlocked_recipes.duplicate(),
		"quick_brew_recipes": quick_brew_recipes.duplicate(),
		"sword_box_unlocked": sword_box_unlocked,
		"sword_box_slot": sword_box_slot.duplicate(true),
		"unlocked_steles": unlocked_steles.duplicate(),
		"last_rested_stele_id": last_rested_stele_id,
		"quest_states": quest_states.duplicate(true),
		"unlocked_clues": unlocked_clues.duplicate(),
		"companion_bonds": companion_bonds.duplicate(true),
		"dao_heart_weights": dao_heart_weights.duplicate(true),
		"ink_seals": ink_seals.duplicate(),
		"faction_reputation": faction_reputation.duplicate(true),
		"unlocked_cgs": unlocked_cgs.duplicate(),
		"unlocked_bond_ultimates": unlocked_bond_ultimates.duplicate(),
		"viewed_night_talks": viewed_night_talks.duplicate(),
		"read_dialogues": read_dialogues.duplicate(true),
		"world_flags": world_flags.duplicate(true),
		"cleared_encounters": cleared_encounters.duplicate(true),
		"opened_containers": opened_containers.duplicate(true),
	}


func _serialize_party_members() -> Dictionary:
	var out: Dictionary = {}
	for cid_var: Variant in party_members.keys():
		var cid: String = str(cid_var)
		var m: Dictionary = party_members[cid] as Dictionary
		var copy_m: Dictionary = m.duplicate(true)
		copy_m.erase("sheet")
		out[cid] = copy_m
	return out


func deserialize_payload(payload: Dictionary) -> void:
	DataDB.load_all()
	bump_scene_epoch()
	difficulty = str(payload.get("difficulty", "cultivation"))
	chapter_id = str(payload.get("chapter_id", "ch01_qinglan"))
	current_zone_id = str(payload.get("current_zone_id", "tingyu_town"))
	current_spawn_tag = str(payload.get("current_spawn_tag", "town_south_entry"))
	var pos_d: Dictionary = payload.get("saved_player_pos", {}) as Dictionary
	saved_player_pos = Vector2(float(pos_d.get("x", 360.0)), float(pos_d.get("y", 640.0)))
	playtime_sec = float(payload.get("playtime_sec", 0.0))
	spirit_stones = int(payload.get("spirit_stones", 120))
	active_formation_id = str(payload.get("active_formation_id", "scatter"))
	unlocked_formations = _to_str_array(payload.get("unlocked_formations", ["scatter"]) as Array)
	formation_slots = _to_str_array(payload.get("formation_slots", ["gu_changqing", "", "", ""]) as Array)
	while formation_slots.size() < 4:
		formation_slots.append("")
	if formation_slots[1] == "" and formation_slots[2] != "" and formation_slots[3] == "":
		formation_slots[1] = formation_slots[2]
		formation_slots[2] = ""
	recruited_order = _to_str_array(payload.get("recruited_order", ["gu_changqing"]) as Array)
	controlled_slot = int(payload.get("controlled_slot", 1))
	if controlled_slot >= 1 and controlled_slot <= 4 and formation_slots[controlled_slot - 1] == "":
		controlled_slot = 1

	party_members.clear()
	_init_member_state("gu_changqing", "mortal", true)
	_init_member_state("shen_qinghe", "qi_refining_1", false)
	_init_member_state("pei_zhao", "qi_refining_2", false)
	var saved_pm: Dictionary = payload.get("party_members", {}) as Dictionary
	for cid_var: Variant in saved_pm.keys():
		var cid: String = str(cid_var)
		if saved_pm[cid] is Dictionary:
			party_members[cid] = (saved_pm[cid] as Dictionary).duplicate(true)

	active_pet_id = str(payload.get("active_pet_id", ""))
	unlocked_pets = _to_str_array(payload.get("unlocked_pets", []) as Array)
	pet_stance = str(payload.get("pet_stance", "assist"))
	pet_hp_ratio = float(payload.get("pet_hp_ratio", 1.0))

	inventory.clear()
	for raw_it: Variant in (payload.get("inventory", []) as Array):
		if raw_it is Dictionary:
			inventory.append((raw_it as Dictionary).duplicate(true))
	quick_pill_5_id = str(payload.get("quick_pill_5_id", "item_huichun_powder"))
	quick_pill_6_id = str(payload.get("quick_pill_6_id", "item_qingmu_pill"))
	active_elixir = (payload.get("active_elixir", {}) as Dictionary).duplicate(true)

	unlocked_recipes = _to_str_array(payload.get("unlocked_recipes", ["recipe_huichun_powder"]) as Array)
	quick_brew_recipes = _to_str_array(payload.get("quick_brew_recipes", []) as Array)
	sword_box_unlocked = bool(payload.get("sword_box_unlocked", true))
	sword_box_slot = (payload.get("sword_box_slot", {}) as Dictionary).duplicate(true)

	unlocked_steles = _to_str_array(payload.get("unlocked_steles", ["stele_tingyu_gate"]) as Array)
	last_rested_stele_id = str(payload.get("last_rested_stele_id", "stele_tingyu_gate"))
	quest_states = (payload.get("quest_states", {}) as Dictionary).duplicate(true)
	unlocked_clues = _to_str_array(payload.get("unlocked_clues", []) as Array)
	companion_bonds = (payload.get("companion_bonds", {"shen_qinghe": 1, "pei_zhao": 1}) as Dictionary).duplicate(true)
	dao_heart_weights = (payload.get("dao_heart_weights", {"lone_peak": 0, "mortal_mercy": 0, "seek_truth": 0}) as Dictionary).duplicate(true)
	ink_seals = _to_str_array(payload.get("ink_seals", []) as Array)
	faction_reputation = (payload.get("faction_reputation", {}) as Dictionary).duplicate(true)
	unlocked_cgs = _to_str_array(payload.get("unlocked_cgs", []) as Array)
	unlocked_bond_ultimates = _to_str_array(payload.get("unlocked_bond_ultimates", []) as Array)
	viewed_night_talks = _to_str_array(payload.get("viewed_night_talks", []) as Array)
	read_dialogues = (payload.get("read_dialogues", {}) as Dictionary).duplicate(true)
	world_flags = (payload.get("world_flags", {}) as Dictionary).duplicate(true)
	cleared_encounters = (payload.get("cleared_encounters", {}) as Dictionary).duplicate(true)
	opened_containers = (payload.get("opened_containers", {}) as Dictionary).duplicate(true)

	recalculate_all_party_stats(false)
	party_updated.emit()
	inventory_updated.emit()
	journal_updated.emit()


func _to_str_array(raw: Array) -> Array[String]:
	var out: Array[String] = []
	for item: Variant in raw:
		out.append(str(item))
	return out
