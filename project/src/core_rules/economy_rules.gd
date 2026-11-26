class_name EconomyRules
extends RefCounted
## 第一层核心规则：唯一通用货币【灵石】防套利定价、五大声望阶位折扣、
## 15s 首炼文武控火判定、【断玉剑匣】废丹提纯与 100% 妖核无损回炉规则。
## 严格对齐 docs/design/13-economy-and-crafting.md。

const SELL_RATIO: float = 0.35
const SWORD_BOX_PURIFY_BATTLES: int = 3

const REPUTATION_TIERS: Array[Dictionary] = [
	{"tier": 0, "min_rep": 0, "name_key": "REP_TIER_0", "discount_mult": 1.00},
	{"tier": 1, "min_rep": 1000, "name_key": "REP_TIER_1", "discount_mult": 0.95},
	{"tier": 2, "min_rep": 3000, "name_key": "REP_TIER_2", "discount_mult": 0.92},
	{"tier": 3, "min_rep": 6000, "name_key": "REP_TIER_3", "discount_mult": 0.88},
	{"tier": 4, "min_rep": 10000, "name_key": "REP_TIER_4", "discount_mult": 0.85},
]


static func get_reputation_tier_info(rep_points: int) -> Dictionary:
	var best: Dictionary = REPUTATION_TIERS[0]
	for entry: Dictionary in REPUTATION_TIERS:
		if rep_points >= int(entry.get("min_rep", 0)):
			best = entry
	return best.duplicate()


static func compute_buy_price(base_buy_price: int, faction_rep: int = 0) -> int:
	if base_buy_price <= 0:
		return 0
	var tier_info: Dictionary = get_reputation_tier_info(faction_rep)
	var disc: float = float(tier_info.get("discount_mult", 1.0))
	return maxi(1, int(round(float(base_buy_price) * disc)))


static func compute_sell_price(base_buy_price: int, explicit_sell_price: int = -1) -> int:
	if explicit_sell_price >= 0:
		var cap_price: int = int(floor(float(maxi(1, base_buy_price)) * SELL_RATIO))
		return maxi(1, mini(explicit_sell_price, cap_price))
	if base_buy_price <= 0:
		return 1
	return maxi(1, int(floor(float(base_buy_price) * SELL_RATIO)))


## 校验配方是否存在“商店买草 -> 炼丹 -> 卖回商店”套利死循环
static func is_recipe_arbitrage_safe(recipe_def: Dictionary, item_defs: Dictionary) -> bool:
	var output_id: String = str(recipe_def.get("output_item_id", ""))
	var out_def: Dictionary = _as_dict(item_defs.get(output_id, {}))
	var out_sell: int = compute_sell_price(
		int(out_def.get("buy_price", 20)),
		int(out_def.get("sell_price", -1))
	)
	var flawless_sell: int = int(floor(float(out_sell) * 1.2))
	var ingredients: Array = recipe_def.get("ingredients", []) as Array
	var min_discounted_shop_cost: int = 0
	for raw_ing: Variant in ingredients:
		if not (raw_ing is Dictionary):
			continue
		var ing: Dictionary = raw_ing as Dictionary
		var mat_id: String = str(ing.get("item_id", ""))
		var qty: int = maxi(1, int(ing.get("count", 1)))
		var mat_def: Dictionary = _as_dict(item_defs.get(mat_id, {}))
		var mat_buy: int = int(mat_def.get("buy_price", 9999))
		# 按最高 85 折计算最低可能进货成本，确保即使生死同盟折扣下也绝不倒挂
		min_discounted_shop_cost += maxi(1, int(floor(float(mat_buy) * 0.85))) * qty
	return flawless_sell < min_discounted_shop_cost


## 首炼 15 秒文武控火三次判定：
## target_phases 为丹方要求的 3 段理想火候（0.0=纯文火 ~ 1.0=烈武火），player_phases 为玩家 3 段输入值
static func evaluate_first_brew_fire(target_phases: Array, player_phases: Array, recipe_def: Dictionary) -> Dictionary:
	var stage_count: int = mini(target_phases.size(), player_phases.size())
	if stage_count <= 0:
		stage_count = 3
	var total_error: float = 0.0
	for i: int in range(stage_count):
		var t_val: float = float(target_phases[i]) if i < target_phases.size() else 0.5
		var p_val: float = float(player_phases[i]) if i < player_phases.size() else 0.5
		total_error += absf(t_val - p_val)
	var avg_error: float = total_error / float(stage_count)

	if avg_error <= 0.14:
		return {
			"quality": "flawless",
			"output_item_id": str(recipe_def.get("flawless_item_id", recipe_def.get("output_item_id", ""))),
			"potency_mult": 1.20,
			"unlock_quick_brew": true,
			"avg_error": avg_error,
			"result_key": "UI_BREW_FLAWLESS",
		}
	elif avg_error <= 0.34:
		return {
			"quality": "standard",
			"output_item_id": str(recipe_def.get("output_item_id", "")),
			"potency_mult": 1.00,
			"unlock_quick_brew": false,
			"avg_error": avg_error,
			"result_key": "UI_BREW_STANDARD",
		}
	return {
		"quality": "burnt",
		"output_item_id": str(recipe_def.get("burnt_item_id", "item_burnt_pill")),
		"potency_mult": 0.0,
		"unlock_quick_brew": false,
		"avg_error": avg_error,
		"result_key": "UI_BREW_BURNT",
	}


## 【断玉剑匣 · 混元提纯】规则：废丹 -> 无瑕极品丹，残草 -> 精纯药引（经历 3 场真实战斗或石碑休整完成）
static func resolve_sword_box_purification(input_item_def: Dictionary) -> Dictionary:
	var purify_target: String = str(input_item_def.get("purify_into_item_id", ""))
	var purify_count: int = maxi(1, int(input_item_def.get("purify_into_count", 1)))
	if purify_target == "":
		return {
			"can_purify": false,
			"required_battles": SWORD_BOX_PURIFY_BATTLES,
			"output_item_id": "",
			"output_count": 0,
		}
	return {
		"can_purify": true,
		"required_battles": SWORD_BOX_PURIFY_BATTLES,
		"output_item_id": purify_target,
		"output_count": purify_count,
	}


## 旧装回炉归元：100% 返还核心稀有妖核与点化结晶
static func compute_reforge_refund(equip_def: Dictionary) -> Array[Dictionary]:
	var refunds: Array[Dictionary] = []
	var core_id: String = str(equip_def.get("craft_core_item_id", ""))
	if core_id != "":
		refunds.append({"item_id": core_id, "count": maxi(1, int(equip_def.get("craft_core_count", 1)))})
	var crystal_count: int = int(equip_def.get("enchant_crystal_spent", 0))
	if crystal_count > 0:
		refunds.append({"item_id": "item_enchant_crystal", "count": crystal_count})
	return refunds


static func _as_dict(val: Variant) -> Dictionary:
	if val is Dictionary:
		return val as Dictionary
	return {}
