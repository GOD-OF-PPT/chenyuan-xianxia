extends Node
## 第二层状态服务单例（1/5）：只读 JSON 配表数据库与本地化 CSV 注册器
## 单向依赖：仅引用 core_rules，绝不引用 presentation 场景节点。

var realms: Dictionary = {}
var characters: Dictionary = {}
var pets: Dictionary = {}
var skills: Dictionary = {}
var formations: Dictionary = {}
var equipment: Dictionary = {}
var equip_sets: Dictionary = {}
var items: Dictionary = {}
var recipes: Dictionary = {}
var shops: Dictionary = {}
var enemies: Dictionary = {}
var quests: Dictionary = {}
var journal_entries: Dictionary = {}
var factions: Dictionary = {}
var ink_seals: Dictionary = {}
var cg_gallery: Dictionary = {}
var dialogues: Dictionary = {}

var is_loaded: bool = false
var font_regular: Font = null
var font_bold: Font = null


func _ready() -> void:
	load_all()


func _exit_tree() -> void:
	font_regular = null
	font_bold = null
	UIThemeBuilder.clear_cached_fonts()


func load_all() -> void:
	if is_loaded:
		return
	font_regular = UIThemeBuilder.get_regular_font()
	font_bold = UIThemeBuilder.get_bold_font()
	_register_csv_translations("res://locales/zh_CN.csv")
	TranslationServer.set_locale("zh_CN")

	var realms_doc: Dictionary = _load_json_dict("res://data/realms.json")
	realms = _index_by_id(realms_doc.get("realms", []) as Array)

	var chars_doc: Dictionary = _load_json_dict("res://data/characters.json")
	characters = _index_by_id(chars_doc.get("characters", []) as Array)
	pets = _index_by_id(chars_doc.get("pets", []) as Array)

	var skills_doc: Dictionary = _load_json_dict("res://data/skills.json")
	skills = _index_by_id(skills_doc.get("skills", []) as Array)

	var form_doc: Dictionary = _load_json_dict("res://data/formations.json")
	formations = _index_by_id(form_doc.get("formations", []) as Array)

	var equip_doc: Dictionary = _load_json_dict("res://data/equipment.json")
	equipment = _index_by_id(equip_doc.get("equipment", []) as Array)
	equip_sets = _index_by_id(equip_doc.get("sets", []) as Array)

	var items_doc: Dictionary = _load_json_dict("res://data/items_and_recipes.json")
	items = _index_by_id(items_doc.get("items", []) as Array)
	recipes = _index_by_id(items_doc.get("recipes", []) as Array)
	shops = _index_by_id(items_doc.get("shops", []) as Array)

	var enemy_doc: Dictionary = _load_json_dict("res://data/enemies.json")
	enemies = _index_by_id(enemy_doc.get("enemies", []) as Array)

	var journal_doc: Dictionary = _load_json_dict("res://data/journal_and_factions.json")
	quests = _index_by_id(journal_doc.get("quests", []) as Array)
	journal_entries = _index_by_id(journal_doc.get("journal_entries", []) as Array)
	factions = _index_by_id(journal_doc.get("factions", []) as Array)
	ink_seals = _index_by_id(journal_doc.get("ink_seals", []) as Array)
	cg_gallery = _index_by_id(journal_doc.get("cg_gallery", []) as Array)

	var dlg_doc: Dictionary = _load_json_dict("res://data/dialogues/ch01_dialogues.json")
	dialogues = _index_by_id(dlg_doc.get("dialogues", []) as Array)

	is_loaded = true


func get_realm(realm_id: String) -> Dictionary:
	return _as_dict(realms.get(realm_id, {}))


func get_character(char_id: String) -> Dictionary:
	return _as_dict(characters.get(char_id, {}))


func get_pet(pet_id: String) -> Dictionary:
	return _as_dict(pets.get(pet_id, {}))


func get_skill(skill_id: String) -> Dictionary:
	return _as_dict(skills.get(skill_id, {}))


func get_formation(formation_id: String) -> Dictionary:
	return _as_dict(formations.get(formation_id, {}))


func get_equipment(equip_id: String) -> Dictionary:
	return _as_dict(equipment.get(equip_id, {}))


func get_any_item_or_equip(id: String) -> Dictionary:
	if equipment.has(id):
		return _as_dict(equipment.get(id, {}))
	return _as_dict(items.get(id, {}))


func get_recipe(recipe_id: String) -> Dictionary:
	return _as_dict(recipes.get(recipe_id, {}))


func get_shop(shop_id: String) -> Dictionary:
	return _as_dict(shops.get(shop_id, {}))


func get_enemy(enemy_id: String) -> Dictionary:
	return _as_dict(enemies.get(enemy_id, {}))


func get_dialogue(dialogue_id: String) -> Dictionary:
	return _as_dict(dialogues.get(dialogue_id, {}))


func loc(key_or_text: String) -> String:
	if key_or_text == "":
		return ""
	var translated: String = tr(key_or_text)
	return translated


func _register_csv_translations(csv_path: String) -> void:
	if not FileAccess.file_exists(csv_path):
		if ResourceLoader.exists("res://locales/zh_CN.zh_CN.translation"):
			var tr_res: Translation = load("res://locales/zh_CN.zh_CN.translation") as Translation
			if tr_res != null:
				TranslationServer.add_translation(tr_res)
		return
	var f: FileAccess = FileAccess.open(csv_path, FileAccess.READ)
	if f == null:
		return
	var zh_cn: Translation = Translation.new()
	zh_cn.locale = "zh_CN"
	var header: PackedStringArray = f.get_csv_line()
	var col_idx: int = 1
	for i: int in range(header.size()):
		if header[i].strip_edges() == "zh_CN":
			col_idx = i
			break
	while not f.eof_reached():
		var row: PackedStringArray = f.get_csv_line()
		if row.size() > col_idx:
			var k: String = row[0].strip_edges()
			if k != "" and not k.begins_with("#"):
				zh_cn.add_message(k, row[col_idx].replace("\\n", "\n"))
	f.close()
	TranslationServer.add_translation(zh_cn)


func _load_json_dict(res_path: String) -> Dictionary:
	if not FileAccess.file_exists(res_path):
		push_warning("DataDB missing table: %s" % res_path)
		return {}
	var raw_text: String = FileAccess.get_file_as_string(res_path)
	var parsed: Variant = JSON.parse_string(raw_text)
	if parsed is Dictionary:
		return parsed as Dictionary
	push_error("DataDB invalid JSON in: %s" % res_path)
	return {}


func _index_by_id(entries: Array) -> Dictionary:
	var out: Dictionary = {}
	for raw_item: Variant in entries:
		if raw_item is Dictionary:
			var d: Dictionary = raw_item as Dictionary
			var id_str: String = str(d.get("id", ""))
			if id_str != "":
				out[id_str] = d
	return out


func _as_dict(val: Variant) -> Dictionary:
	if val is Dictionary:
		return val as Dictionary
	return {}
