"""Worker 3 (e2e_tw_3) Python host data, economy, typography, locale & Polish R3 checks.

Covers Features F8, F9, F10, F11 static/data/asset/shader contracts without touching
any formal save directories or ``/tmp``.
"""

from __future__ import annotations

import csv
import json
import math
import re
from pathlib import Path
from typing import Any

from tools.e2e import CheckContext, make_check
from tools.e2e.visual_master_inspector import (
    count_fluorescent_pixels,
    load_gate3_master,
    load_rgba,
    sample_roi_rgb_stats,
    wcag_contrast_ratio,
)

VALID_EQUIP_SLOTS: tuple[str, ...] = ("weapon", "robe", "boots", "pendant", "treasure")
FORBIDDEN_CURRENCY_TOKENS: tuple[str, ...] = (
    "gold_price",
    "diamond_price",
    "gem_price",
    "rmb_price",
    "gacha_ticket",
    "vip_level",
    "battle_pass",
)
FORBIDDEN_MOCKUP_TOKENS: tuple[str, ...] = (
    "丸榲",
    "百榥",
    "白恩",
    "體魄",
    "靈識",
    "真氣",
    "攻擊",
    "防禦",
    "暴擊",
    "Qi 56",
    "濟世堂",
)


def _load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _load_zh_cn_map(csv_path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    with csv_path.open("r", encoding="utf-8", newline="") as fh:
        reader = csv.reader(fh)
        header = next(reader, [])
        col_idx = 1
        for idx, cell in enumerate(header):
            if cell.strip() == "zh_CN":
                col_idx = idx
                break
        for row in reader:
            if len(row) > col_idx:
                key = row[0].strip()
                if key and not key.startswith("#"):
                    out[key] = row[col_idx].replace("\\n", "\n")
    return out


def _res_to_disk(project_dir: Path, res_path: str) -> Path:
    if res_path.startswith("res://"):
        return project_dir / res_path[len("res://") :]
    return project_dir / res_path


def _strip_gdshader_comments(src: str) -> str:
    no_block = re.sub(r"/\*.*?\*/", "", src, flags=re.DOTALL)
    return re.sub(r"//[^\n]*", "", no_block)


def _check_t1_f08_06_realms_and_chars_schema(ctx: CheckContext) -> None:
    realms_doc = _load_json(ctx.project_dir / "data" / "realms.json")
    chars_doc = _load_json(ctx.project_dir / "data" / "characters.json")
    skills_doc = _load_json(ctx.project_dir / "data" / "skills.json")
    zh_map = _load_zh_cn_map(ctx.project_dir / "locales" / "zh_CN.csv")

    realms_list: list[dict[str, Any]] = list(realms_doc.get("realms", []))
    skills_by_id = {str(s.get("id", "")): s for s in skills_doc.get("skills", [])}
    ctx.assert_ge(len(realms_list), 5, "realms.json defines >= 5 progression stages")

    by_id = {str(r.get("id", "")): r for r in realms_list}
    canonical_chain = ["mortal", "qi_refining_1", "qi_refining_2", "qi_refining_3", "foundation_1"]
    prev_idx = -1
    prev_k = 0.0
    prev_hp = 0.0
    prev_power = 0.0

    for rid in canonical_chain:
        ctx.assert_true(rid in by_id, f"Canonical realm '{rid}' exists in realms.json")
        if rid not in by_id:
            continue
        rdef = by_id[rid]
        sub_idx = int(rdef.get("sub_realm_total_index", -1))
        k_val = float(rdef.get("k_realm", 0.0))
        base_hp = float(rdef.get("base_hp", 0.0))
        base_pwr = float(rdef.get("base_power", 0.0))
        life_max = int(rdef.get("lifespan_max", 0))

        ctx.assert_gt(sub_idx, prev_idx, f"Realm '{rid}' sub_realm_total_index strictly increases")
        ctx.assert_gt(k_val, prev_k, f"Realm '{rid}' k_realm strictly increases for hyperbolic scaling")
        ctx.assert_gt(base_hp, prev_hp, f"Realm '{rid}' base_hp strictly increases")
        ctx.assert_gt(base_pwr, prev_power, f"Realm '{rid}' base_power strictly increases")
        ctx.assert_ge(life_max, 80, f"Realm '{rid}' lifespan_max >= 80")

        for kfield in ("name_key", "sub_name_key", "desc_key"):
            lkey = str(rdef.get(kfield, ""))
            ctx.assert_true(
                bool(lkey) and lkey in zh_map and bool(zh_map[lkey].strip()),
                f"Realm '{rid}' {kfield}='{lkey}' resolves in zh_CN.csv",
            )
        prev_idx, prev_k, prev_hp, prev_power = sub_idx, k_val, base_hp, base_pwr

    chars_by_id = {str(c.get("id", "")): c for c in chars_doc.get("characters", [])}
    for cid in ("gu_changqing", "shen_qinghe", "pei_zhao"):
        ctx.assert_true(cid in chars_by_id, f"Playable character '{cid}' exists in characters.json")
        if cid not in chars_by_id:
            continue
        cdef = chars_by_id[cid]
        five = dict(cdef.get("base_five_stats", {}))
        for sk in ("con", "spi", "str", "end", "agi"):
            ctx.assert_gt(float(five.get(sk, 0.0)), 0.0, f"Character '{cid}' base stat '{sk}' > 0")
        specs = dict(cdef.get("specializations", {}))
        for spec_key in ("spec_a", "spec_b"):
            ctx.assert_true(spec_key in specs, f"Character '{cid}' defines {spec_key}")
            sp_def = dict(specs.get(spec_key, {}))
            nodes = list(sp_def.get("nodes", []))
            ctx.assert_eq(len(nodes), 3, f"Character '{cid}' {spec_key} has 3 realm-gated nodes")
            bar = dict(sp_def.get("skill_bar", {}))
            for slot_k, skid in bar.items():
                ctx.assert_true(
                    str(skid) in skills_by_id,
                    f"Character '{cid}' {spec_key} slot '{slot_k}' skill '{skid}' exists in skills.json",
                )

    ctx.record_metric("realm_count", len(realms_list))
    ctx.record_metric("character_count", len(chars_by_id))


def _check_t2_f09_06_equipment_fk_and_icons(ctx: CheckContext) -> None:
    eq_doc = _load_json(ctx.project_dir / "data" / "equipment.json")
    skills_doc = _load_json(ctx.project_dir / "data" / "skills.json")
    items_doc = _load_json(ctx.project_dir / "data" / "items_and_recipes.json")
    zh_map = _load_zh_cn_map(ctx.project_dir / "locales" / "zh_CN.csv")

    sets_list: list[dict[str, Any]] = list(eq_doc.get("sets", []))
    equip_list: list[dict[str, Any]] = list(eq_doc.get("equipment", []))
    sets_by_id = {str(s.get("id", "")): s for s in sets_list}
    skills_by_id = {str(s.get("id", "")): s for s in skills_doc.get("skills", [])}
    shops_list: list[dict[str, Any]] = list(items_doc.get("shops", []))
    all_shop_stock = {
        str(sid) for shop in shops_list for sid in shop.get("stock", [])
    }

    ctx.assert_ge(len(sets_list), 3, "equipment.json defines >= 3 sect sets")
    ctx.assert_ge(len(equip_list), 15, "equipment.json defines >= 15 artifacts")

    for sdef in sets_list:
        sid = str(sdef.get("id", ""))
        for kfield in ("name_key", "desc_2pc_key", "desc_3pc_key"):
            lkey = str(sdef.get(kfield, ""))
            ctx.assert_true(
                lkey in zh_map and bool(zh_map[lkey].strip()),
                f"Set '{sid}' {kfield}='{lkey}' resolves in zh_CN.csv",
            )

    treasure_ids: list[str] = []
    blue_stunt_equips: list[str] = []
    for edef in equip_list:
        eid = str(edef.get("id", ""))
        slot = str(edef.get("slot", ""))
        ctx.assert_true(slot in VALID_EQUIP_SLOTS, f"Equipment '{eid}' slot '{slot}' is valid")

        for kfield in ("name_key", "desc_key"):
            lkey = str(edef.get(kfield, ""))
            ctx.assert_true(
                lkey in zh_map and bool(zh_map[lkey].strip()),
                f"Equipment '{eid}' {kfield}='{lkey}' resolves in zh_CN.csv",
            )

        set_id = str(edef.get("set_id", ""))
        if set_id:
            ctx.assert_true(set_id in sets_by_id, f"Equipment '{eid}' set_id '{set_id}' exists")

        stunt_id = str(edef.get("blue_stunt_id", ""))
        if stunt_id:
            blue_stunt_equips.append(eid)
            ctx.assert_true(stunt_id in skills_by_id, f"Blue stunt '{stunt_id}' on '{eid}' exists")
            if stunt_id in skills_by_id:
                st_def = skills_by_id[stunt_id]
                ctx.assert_true(
                    bool(st_def.get("is_blue_stunt", False)),
                    f"Skill '{stunt_id}' has is_blue_stunt == true",
                )
                ctx.assert_gt(
                    float(st_def.get("attunement_cost", 0.0)),
                    0.0,
                    f"Blue stunt '{stunt_id}' consumes team attunement Qi",
                )

        tr_sk = str(edef.get("treasure_skill_id", ""))
        if tr_sk:
            ctx.assert_true(tr_sk in skills_by_id, f"Treasure skill '{tr_sk}' on '{eid}' exists")

        if slot == "treasure":
            treasure_ids.append(eid)
            allowed = list(edef.get("allowed_characters", []))
            ctx.assert_eq(
                len(allowed),
                1,
                f"Natal Treasure '{eid}' is bound to exactly 1 character ({allowed})",
            )
            ctx.assert_eq(int(edef.get("buy_price", -1)), 0, f"Treasure '{eid}' buy_price == 0")
            ctx.assert_eq(int(edef.get("sell_price", -1)), 0, f"Treasure '{eid}' sell_price == 0")
            ctx.assert_false(eid in all_shop_stock, f"Treasure '{eid}' excluded from shop stock")

        icon_res = str(edef.get("icon", ""))
        icon_disk = _res_to_disk(ctx.project_dir, icon_res)
        ctx.assert_true(icon_disk.is_file(), f"Equipment '{eid}' icon exists at {icon_res}")
        if icon_disk.is_file():
            rgba = load_rgba(icon_disk)
            ctx.assert_gt(int((rgba[..., 3] > 16).sum()), 32, f"Icon '{icon_res}' has non-empty alpha")
            ctx.assert_eq(
                count_fluorescent_pixels(rgba),
                0,
                f"Icon '{icon_res}' has 0 fluorescent neon pixels",
            )

    ctx.assert_ge(len(treasure_ids), 3, "At least 3 character Natal Treasures verified")
    ctx.assert_ge(len(blue_stunt_equips), 2, "At least 2 blue-stunt artifacts verified")
    ctx.record_metric("equipment_count", len(equip_list))
    ctx.record_metric("blue_stunt_equip_count", len(blue_stunt_equips))


def _check_t2_f10_06_zero_arbitrage_and_sole_currency(ctx: CheckContext) -> None:
    items_raw = (ctx.project_dir / "data" / "items_and_recipes.json").read_text(encoding="utf-8")
    equip_raw = (ctx.project_dir / "data" / "equipment.json").read_text(encoding="utf-8")
    zh_raw = (ctx.project_dir / "locales" / "zh_CN.csv").read_text(encoding="utf-8")

    for bad_tok in FORBIDDEN_CURRENCY_TOKENS:
        ctx.assert_false(bad_tok in items_raw, f"Forbidden currency '{bad_tok}' absent from items JSON")
        ctx.assert_false(bad_tok in equip_raw, f"Forbidden currency '{bad_tok}' absent from equipment JSON")
        ctx.assert_false(bad_tok in zh_raw, f"Forbidden currency '{bad_tok}' absent from zh_CN.csv")

    items_doc = json.loads(items_raw)
    eq_doc = json.loads(equip_raw)
    zh_map = _load_zh_cn_map(ctx.project_dir / "locales" / "zh_CN.csv")
    ctx.assert_eq(zh_map.get("TERM_SPIRIT_STONE"), "灵石", "Sole currency TERM_SPIRIT_STONE == '灵石'")

    merged_defs: dict[str, dict[str, Any]] = {}
    for entry in list(items_doc.get("items", [])) + list(eq_doc.get("equipment", [])):
        merged_defs[str(entry.get("id", ""))] = entry

    sellable_checked = 0
    for iid, idef in merged_defs.items():
        if bool(idef.get("unsellable", False)):
            continue
        cat = str(idef.get("category", ""))
        if cat in ("quest", "storage_pouch") or str(idef.get("slot", "")) == "treasure":
            continue
        buy_p = int(idef.get("buy_price", 0))
        sell_p = int(idef.get("sell_price", 0))
        if buy_p > 0:
            cap_p = int(math.floor(buy_p * 0.35))
            ctx.assert_le(
                sell_p,
                cap_p,
                f"Sellable '{iid}' sell_price={sell_p} <= floor({buy_p}*0.35)={cap_p}",
            )
            sellable_checked += 1

        purify_target = str(idef.get("purify_into_item_id", ""))
        if purify_target:
            ctx.assert_true(
                purify_target in merged_defs,
                f"Sword Box purify target '{purify_target}' from '{iid}' exists in DataDB",
            )

    ctx.assert_ge(sellable_checked, 15, "Verified >= 15 sellable items against 35% price cap")

    recipes: list[dict[str, Any]] = list(items_doc.get("recipes", []))
    ctx.assert_ge(len(recipes), 3, "At least 3 Chapter 1 alchemy recipes defined")
    for rdef in recipes:
        rid = str(rdef.get("id", ""))
        out_id = str(rdef.get("output_item_id", ""))
        flawless_id = str(rdef.get("flawless_item_id", ""))
        ctx.assert_true(out_id in merged_defs, f"Recipe '{rid}' output '{out_id}' exists")
        ctx.assert_true(flawless_id in merged_defs, f"Recipe '{rid}' flawless '{flawless_id}' exists")

        out_def = merged_defs.get(out_id, {})
        out_buy = max(1, int(out_def.get("buy_price", 20)))
        explicit_sell = int(out_def.get("sell_price", -1))
        cap_sell = max(1, int(math.floor(out_buy * 0.35)))
        out_sell = max(1, min(explicit_sell, cap_sell)) if explicit_sell >= 0 else cap_sell
        flawless_sell = int(math.floor(out_sell * 1.2))

        min_disc_cost = 0
        for ing in rdef.get("ingredients", []):
            mid = str(ing.get("item_id", ""))
            qty = max(1, int(ing.get("count", 1)))
            ctx.assert_true(mid in merged_defs, f"Recipe '{rid}' ingredient '{mid}' exists")
            mat_buy = int(merged_defs.get(mid, {}).get("buy_price", 9999))
            min_disc_cost += max(1, int(math.floor(mat_buy * 0.85))) * qty

        ctx.assert_lt(
            flawless_sell,
            min_disc_cost,
            f"Recipe '{rid}' zero-arbitrage holds: flawless_sell={flawless_sell} < 85%-rep cost={min_disc_cost}",
        )

        targets = list(rdef.get("fire_targets", []))
        ctx.assert_eq(len(targets), 3, f"Recipe '{rid}' defines 3-stage fire_targets")
        for t_val in targets:
            ctx.assert_true(0.05 <= float(t_val) <= 0.95, f"Recipe '{rid}' fire target {t_val} in [0.05,0.95]")

    for shop in items_doc.get("shops", []):
        sh_id = str(shop.get("id", ""))
        for st_id in shop.get("stock", []):
            ctx.assert_true(
                str(st_id) in merged_defs,
                f"Shop '{sh_id}' stock item '{st_id}' exists",
            )

    ctx.record_metric("recipes_verified", len(recipes))
    ctx.record_metric("sellable_items_verified", sellable_checked)


def _check_t1_f11_06_fonts_wcag_and_master_d_plate(ctx: CheckContext) -> None:
    for fname in ("NotoSerifCJKsc-Regular.otf", "NotoSerifCJKsc-Bold.otf"):
        fpath = ctx.project_dir / "assets" / "fonts" / fname
        ctx.assert_true(fpath.is_file(), f"Font asset '{fname}' exists")
        if fpath.is_file():
            fsize = fpath.stat().st_size
            ctx.assert_gt(fsize, 1_000_000, f"Font '{fname}' is full CJK font (>1MB)")
            with fpath.open("rb") as fh:
                magic = fh.read(4)
            ctx.assert_true(
                magic in (b"OTTO", b"\x00\x01\x00\x00"),
                f"Font '{fname}' has valid OpenType/TrueType header ({magic!r})",
            )

    xuan_vs_ink = wcag_contrast_ratio((216, 206, 190), (32, 27, 24))
    ebony_vs_gold = wcag_contrast_ratio((28, 25, 23), (214, 168, 90))
    ebony_vs_xuan = wcag_contrast_ratio((28, 25, 23), (229, 221, 208))
    ctx.assert_ge(xuan_vs_ink, 9.0, "Xuan paper (#D8CEBE) vs Ink (#201B18) WCAG contrast >= 9.0:1")
    ctx.assert_ge(ebony_vs_gold, 6.5, "Ebony (#1C1917) vs Bronze-Gold (#D6A85A) WCAG contrast >= 6.5:1")
    ctx.assert_ge(ebony_vs_xuan, 11.0, "Ebony (#1C1917) vs Warm Xuan (#E5DDD0) WCAG contrast >= 11.0:1")

    master_d = load_gate3_master(ctx.repo_root, "d")
    ctx.assert_eq(master_d.shape, (1080, 1920, 3), "Gate 3 master_d_dao_casket.png is 1920x1080 RGB")
    fluo_px = count_fluorescent_pixels(master_d)
    ctx.assert_eq(fluo_px, 0, "master_d_dao_casket.png has 0 fluorescent pixels")

    border_stats = sample_roi_rgb_stats(master_d, (0, 0, 1920, 28))
    page_stats = sample_roi_rgb_stats(master_d, (140, 175, 520, 300))
    ctx.assert_lt(border_stats["mean_luma"], 48.0, "master_d outer ebony frame is dark (<48/255 luma)")
    ctx.assert_gt(page_stats["mean_luma"], 145.0, "master_d Xuan paper spread is bright (>145/255 luma)")
    ctx.assert_gt(page_stats["mean_r"], page_stats["mean_b"], "master_d Xuan paper has warm R > B tone")

    ctx.record_metric("wcag_xuan_ink", round(xuan_vs_ink, 2))
    ctx.record_metric("wcag_ebony_gold", round(ebony_vs_gold, 2))


def _check_t2_f11_06_static_font_floor_and_clean_zh_cn(ctx: CheckContext) -> None:
    zh_csv_path = ctx.project_dir / "locales" / "zh_CN.csv"
    zh_raw = zh_csv_path.read_text(encoding="utf-8")
    zh_map = _load_zh_cn_map(zh_csv_path)
    ctx.assert_ge(len(zh_map), 80, "zh_CN.csv contains >= 80 localized UI/story entries")

    for bad in FORBIDDEN_MOCKUP_TOKENS:
        ctx.assert_false(
            bad in zh_raw,
            f"Generative plate artifact/Traditional token '{bad}' absent from zh_CN.csv",
        )

    all_zh_values = "\n".join(zh_map.values())
    for required_csv_term in (
        "五维",
        "气血",
        "真元",
        "灵石",
        "济世药庐",
        "修行·兵甲 (C)",
        "道途·奇门 (N)",
        "行囊·剑匣 (B)",
        "问道手札 (J)",
    ):
        ctx.assert_str_contains(
            all_zh_values,
            required_csv_term,
            f"Canonical Simplified Chinese term '{required_csv_term}' present in zh_CN.csv",
        )

    casket_src = (
        ctx.project_dir / "src" / "presentation" / "ui" / "dao_casket_panel.gd"
    ).read_text(encoding="utf-8")
    combined_ui_corpus = all_zh_values + "\n" + casket_src
    for stat_term in ("根骨", "灵识", "膂力", "体魄", "身法"):
        ctx.assert_str_contains(
            combined_ui_corpus,
            stat_term,
            f"Canonical Simplified Chinese five-stat term '{stat_term}' present in UI/locale corpus",
        )

    font_override_re = re.compile(
        r"""(?:add_theme_font_size_override|set_font_size)\s*\(\s*["'][^"']+["']\s*,\s*(\d+)\s*\)"""
    )
    prop_font_re = re.compile(r"""\b(?:default_font_size|font_size)\s*=\s*(\d+)\b""")
    draw_str_re = re.compile(
        r"""draw_string\s*\([^,]+,[^,]+,[^,]+,[^,]+,[^,]+,\s*(\d+)\b"""
    )

    offenders: list[str] = []
    scanned_files = 0
    for ext in ("*.gd", "*.tscn"):
        for fpath in sorted(ctx.project_dir.rglob(ext)):
            rel = fpath.relative_to(ctx.project_dir).as_posix()
            if rel.startswith(".godot/") or rel.startswith("tests/"):
                continue
            scanned_files += 1
            text = fpath.read_text(encoding="utf-8")
            for lineno, line in enumerate(text.splitlines(), start=1):
                code_part = line.split("#", 1)[0]
                for rx in (font_override_re, prop_font_re, draw_str_re):
                    for m in rx.finditer(code_part):
                        px = int(m.group(1))
                        if px < 16:
                            offenders.append(f"{rel}:{lineno} ({px}px)")

    ctx.assert_gt(scanned_files, 15, "Scanned > 15 project .gd/.tscn files")
    ctx.assert_eq(
        offenders,
        [],
        f"100% of static font_size declarations across project .gd/.tscn are >= 16px (offenders={offenders})",
    )
    ctx.record_metric("scanned_gd_tscn_files", scanned_files)


def _check_t2_f11_07_polish_r3_shader_and_tome_assets(ctx: CheckContext) -> None:
    shader_path = ctx.project_dir / "src" / "presentation" / "shaders" / "hover_outline.gdshader"
    ctx.assert_true(
        shader_path.is_file(),
        "Polish R3 shader project/src/presentation/shaders/hover_outline.gdshader exists",
    )
    if shader_path.is_file():
        clean_code = _strip_gdshader_comments(shader_path.read_text(encoding="utf-8"))
        ctx.assert_str_contains(
            clean_code,
            "shader_type canvas_item;",
            "hover_outline.gdshader declares 'shader_type canvas_item;'",
        )
        has_unshaded = bool(re.search(r"\brender_mode\b[^;]*\bunshaded\b", clean_code))
        ctx.assert_false(
            has_unshaded,
            "hover_outline.gdshader MUST remain shaded (0 'render_mode unshaded;' tokens per PROJECT.md:90)",
        )

    ui_dir = ctx.project_dir / "assets" / "ui"
    ui_pngs = [
        p
        for p in sorted(ui_dir.rglob("*.png"))
        if "masters" not in p.parts and "cursors" not in p.parts
    ]
    tome_plates = [
        p
        for p in ui_pngs
        if any(k in p.stem.lower() for k in ("casket", "tome", "xuan_book", "book_spread"))
    ]
    meridian_plates = [
        p
        for p in ui_pngs
        if any(k in p.stem.lower() for k in ("meridian", "acupoint", "vein_figure", "jingmai"))
    ]
    alchemy_plates = [
        p
        for p in ui_pngs
        if any(k in p.stem.lower() for k in ("cauldron", "furnace", "alchemy_flame", "fire_gauge"))
    ]

    ctx.assert_ge(
        len(tome_plates),
        1,
        "Polish R3 provides dedicated thread-bound Xuan tome frame/spread texture(s) under assets/ui/",
    )
    ctx.assert_ge(
        len(meridian_plates),
        1,
        "Polish R3 provides classical brush-ink human meridian diagram texture(s) under assets/ui/",
    )
    ctx.assert_ge(
        len(alchemy_plates),
        1,
        "Polish R3 provides bronze cauldron / flickering flame UI texture(s) under assets/ui/",
    )

    for plate in [*tome_plates, *meridian_plates, *alchemy_plates]:
        rgba = load_rgba(plate)
        h, w = int(rgba.shape[0]), int(rgba.shape[1])
        ctx.assert_eq(
            count_fluorescent_pixels(rgba),
            0,
            f"Polish R3 UI asset '{plate.name}' has 0 fluorescent pixels",
        )
        if w > 1024 or h > 1024:
            imp_path = plate.with_name(plate.name + ".import")
            ctx.assert_true(imp_path.is_file(), f"Large UI plate '{plate.name}' has .import file")
            if imp_path.is_file():
                imp_txt = imp_path.read_text(encoding="utf-8")
                ctx.assert_str_contains(
                    imp_txt,
                    "compress/mode=1",
                    f"Large UI plate '{plate.name}' ({w}x{h}) uses lossy compress/mode=1 (<85MB budget)",
                )


def get_checks() -> list[dict[str, Any]]:
    return [
        make_check(
            "T1-F08-06",
            1,
            "F8",
            "baseline",
            "Realms & characters JSON progression chain, k_realm scaling, 5-stats & dual-spec schema",
            _check_t1_f08_06_realms_and_chars_schema,
        ),
        make_check(
            "T2-F09-06",
            2,
            "F9",
            "baseline",
            "Equipment, sect sets & blue-stunt/treasure skill FK, secrecy & icon palette audit",
            _check_t2_f09_06_equipment_fk_and_icons,
        ),
        make_check(
            "T2-F10-06",
            2,
            "F10",
            "baseline",
            "Sole Spirit-Stone currency, <=35% sell ratio & 100% recipe zero-arbitrage data audit",
            _check_t2_f10_06_zero_arbitrage_and_sole_currency,
        ),
        make_check(
            "T1-F11-06",
            1,
            "F11",
            "baseline",
            "NotoSerifCJKsc OTF fonts, Song-Ming WCAG contrast & master_d_dao_casket.png benchmark",
            _check_t1_f11_06_fonts_wcag_and_master_d_plate,
        ),
        make_check(
            "T2-F11-06",
            2,
            "F11",
            "baseline",
            "Project-wide >=16px static font floor & zero master_d/master_b mockup gibberish in zh_CN.csv",
            _check_t2_f11_06_static_font_floor_and_clean_zh_cn,
        ),
        make_check(
            "T2-F11-07",
            2,
            "F11",
            "polish_r3",
            "Polish R3 shaded hover_outline.gdshader & Xuan tome/meridian/cauldron UI plate budget",
            _check_t2_f11_07_polish_r3_shader_and_tome_assets,
        ),
    ]
