"""Worker 1 Python host, asset, shader & Gate-3 master_b forensics checks (F1, F2, F3, F5)."""

from __future__ import annotations

import csv
import hashlib
import json
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

_COMMENT_BLOCK_RE = re.compile(r"/\*.*?\*/", re.DOTALL)
_COMMENT_LINE_RE = re.compile(r"//[^\n]*")
_RENDER_MODE_RE = re.compile(r"\brender_mode\s+([^;]+);")


def _strip_shader_comments(src: str) -> str:
    no_block = _COMMENT_BLOCK_RE.sub("", src)
    return _COMMENT_LINE_RE.sub("", no_block)


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _load_zh_cn_map(csv_path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    with csv_path.open("r", encoding="utf-8-sig", newline="") as fh:
        reader = csv.reader(fh)
        header = next(reader, None)
        zh_idx = 1
        if header:
            for idx, col in enumerate(header):
                if col.strip().lower().startswith("zh"):
                    zh_idx = idx
                    break
        for row in reader:
            if len(row) > zh_idx and row[0].strip():
                out[row[0].strip()] = row[zh_idx].strip()
    return out


def _check_t1_f01_data_contracts(ctx: CheckContext) -> None:
    data_dir = ctx.project_dir / "data"
    chars_raw = json.loads((data_dir / "characters.json").read_text(encoding="utf-8"))
    skills_raw = json.loads((data_dir / "skills.json").read_text(encoding="utf-8"))
    enemies_raw = json.loads((data_dir / "enemies.json").read_text(encoding="utf-8"))
    items_raw = json.loads((data_dir / "items_and_recipes.json").read_text(encoding="utf-8"))

    skills_by_id: dict[str, dict[str, Any]] = {
        str(s["id"]): s for s in skills_raw.get("skills", []) if isinstance(s, dict) and "id" in s
    }
    chars_by_id: dict[str, dict[str, Any]] = {
        str(c["id"]): c for c in chars_raw.get("characters", []) if isinstance(c, dict) and "id" in c
    }
    enemies_by_id: dict[str, dict[str, Any]] = {
        str(e["id"]): e for e in enemies_raw.get("enemies", []) if isinstance(e, dict) and "id" in e
    }
    items_by_id: dict[str, dict[str, Any]] = {
        str(it["id"]): it for it in items_raw.get("items", []) if isinstance(it, dict) and "id" in it
    }

    expected_chars = ("gu_changqing", "shen_qinghe", "pei_zhao")
    required_slots = ("1", "2", "3", "4", "Q", "E", "R")
    for cid in expected_chars:
        ctx.assert_true(cid in chars_by_id, f"Character '{cid}' present in characters.json")
        cdef = chars_by_id.get(cid, {})
        presets = cdef.get("ai_presets", [])
        ctx.assert_eq(len(presets), 3, f"Character '{cid}' defines exactly 3 AI presets")
        specs = cdef.get("specializations", {})
        for spec_key in ("spec_a", "spec_b"):
            ctx.assert_true(spec_key in specs, f"'{cid}' defines '{spec_key}'")
            bar = specs.get(spec_key, {}).get("skill_bar", {})
            for slot in required_slots:
                sk_id = str(bar.get(slot, ""))
                ctx.assert_true(
                    sk_id in skills_by_id,
                    f"'{cid}.{spec_key}' slot '{slot}' -> '{sk_id}' exists in skills.json",
                )
            q_sk = skills_by_id.get(str(bar.get("Q", "")), {})
            ctx.assert_false(
                bool(q_sk.get("uses_gcd", True)),
                f"'{cid}.{spec_key}' Q skill '{q_sk.get('id')}' is strictly off-GCD",
            )
            ctx.assert_true(
                bool(q_sk.get("is_interrupt", False)),
                f"'{cid}.{spec_key}' Q skill '{q_sk.get('id')}' has is_interrupt=true",
            )

    ult = skills_by_id.get("ult_qinglian_sword", {})
    ctx.assert_true(bool(ult), "ult_qinglian_sword exists in skills.json")
    ctx.assert_false(bool(ult.get("uses_gcd", True)), "ult_qinglian_sword is off-GCD")
    ctx.assert_true(bool(ult.get("is_bond_ultimate", False)), "ult_qinglian_sword marked is_bond_ultimate")
    ctx.assert_approx(float(ult.get("attunement_cost", 0.0)), 100.0, 0.01, "ult_qinglian_sword costs 100 Qi")

    boss = enemies_by_id.get("boss_mist_wolf_king", {})
    ctx.assert_true(bool(boss), "boss_mist_wolf_king exists in enemies.json")
    ctx.assert_eq(int(boss.get("max_hp", 0)), 4200, "Boss Mist Wolf King max_hp == 4200")
    ctx.assert_approx(float(boss.get("ward_max", 0.0)), 450.0, 0.01, "Boss ward_max == 450.0")
    ctx.assert_eq(str(boss.get("ward_element", "")), "wood", "Boss ward_element == 'wood'")
    ctx.assert_approx(float(boss.get("phase2_hp_ratio", 0.0)), 0.55, 0.001, "Boss phase2_hp_ratio == 0.55")
    ctx.assert_eq(str(boss.get("formation_id", "")), "fengyang", "Boss formation_id == 'fengyang'")

    pounce = skills_by_id.get("sk_boss_fan_pounce", {})
    roar = skills_by_id.get("sk_boss_roar_miasma", {})
    ctx.assert_false(bool(pounce.get("interruptible", True)), "sk_boss_fan_pounce is uninterruptible Dark-Red")
    ctx.assert_eq(str(pounce.get("target_type", "")), "ground_cone", "sk_boss_fan_pounce is ground_cone")
    ctx.assert_true(bool(roar.get("interruptible", False)), "sk_boss_roar_miasma is interruptible Amber-Gold")
    ctx.assert_eq(str(roar.get("target_type", "")), "party_aoe", "sk_boss_roar_miasma is party_aoe")

    for pill_id in ("item_huichun_powder", "item_qingmu_pill"):
        pdef = items_by_id.get(pill_id, {})
        ctx.assert_eq(str(pdef.get("category", "")), "instant_pill", f"{pill_id} is instant_pill")
        ctx.assert_gt(float(pdef.get("heal_hp_pct", 0.0)), 0.15, f"{pill_id} heal_hp_pct > 0.15")

    ctx.record_metric("skill_count", len(skills_by_id))
    ctx.record_metric("enemy_count", len(enemies_by_id))


def _check_t1_f05_polish_r1_assets_and_manifest(ctx: CheckContext) -> None:
    vfx_dir = ctx.project_dir / "assets" / "vfx"
    ui_dir = ctx.project_dir / "assets" / "ui"
    frames_dir = ui_dir / "frames"
    manifest_path = ctx.repo_root / "docs" / "asset-manifest.json"

    ctx.assert_true(vfx_dir.is_dir(), "Polish R1 project/assets/vfx/ directory exists")
    ctx.assert_true(frames_dir.is_dir(), "Polish R1 project/assets/ui/frames/ directory exists")

    vfx_pngs = sorted(vfx_dir.rglob("*.png")) if vfx_dir.is_dir() else []
    ctx.assert_ge(
        len(vfx_pngs),
        4,
        "project/assets/vfx/ contains >= 4 PNG textures (sword/trail, slash arcs, Bagua, particles)",
    )

    ui_pngs = sorted(ui_dir.rglob("*.png")) if ui_dir.is_dir() else []
    frame_pngs = sorted(frames_dir.rglob("*.png")) if frames_dir.is_dir() else []
    ctx.assert_ge(
        len(frame_pngs),
        2,
        "project/assets/ui/frames/ contains carved ebony/gilt-bronze HUD frame & plaque PNGs",
    )

    # Check F1~F3 bust avatar textures in project/assets/ui/ (e.g. avatars/frames/icons)
    avatar_hits = 0
    for token in ("gu", "shen", "pei"):
        matched = [
            p
            for p in ui_pngs
            if token in p.stem.lower()
            and any(k in p.as_posix().lower() for k in ("avatar", "bust", "head", "party", "frame"))
        ]
        if matched:
            avatar_hits += 1
    ctx.assert_eq(
        avatar_hits,
        3,
        "project/assets/ui/ contains F1~F3 bust avatar PNGs for gu_changqing, shen_qinghe, pei_zhao",
    )

    manifest_data = json.loads(manifest_path.read_text(encoding="utf-8"))
    entries_by_path: dict[str, dict[str, Any]] = {
        str(e.get("path", "")): e
        for e in manifest_data.get("assets", [])
        if isinstance(e, dict) and e.get("path")
    }

    inspected = [*vfx_pngs, *frame_pngs]
    max_neon_ratio = 0.0
    for png in inspected:
        rel_path = png.relative_to(ctx.repo_root).as_posix()
        ctx.assert_true(rel_path in entries_by_path, f"'{rel_path}' registered in docs/asset-manifest.json")
        if rel_path in entries_by_path:
            entry = entries_by_path[rel_path]
            actual_sha = _sha256_file(png)
            ctx.assert_eq(actual_sha, str(entry.get("sha256", "")), f"SHA-256 matches for '{rel_path}'")
            src_rel = str(entry.get("source_path", ""))
            ctx.assert_true(
                src_rel.startswith("assets_src/") and (ctx.repo_root / src_rel).exists(),
                f"Provenance source_path '{src_rel}' exists under assets_src/ for '{rel_path}'",
            )
            ctx.assert_true(bool(str(entry.get("license", "")).strip()), f"License populated for '{rel_path}'")

        rgba = load_rgba(png)
        opaque_px = max(1, int((rgba[..., 3] > 0).sum()))
        neon_px = count_fluorescent_pixels(rgba)
        neon_ratio = float(neon_px) / float(opaque_px)
        max_neon_ratio = max(max_neon_ratio, neon_ratio)
        ctx.assert_le(
            neon_ratio,
            0.005,
            f"Polish R1 texture '{rel_path}' stays within Song-Ming mineral palette (neon_ratio <= 0.5%)",
        )

    ctx.record_metric("vfx_png_count", len(vfx_pngs))
    ctx.record_metric("hud_frame_png_count", len(frame_pngs))
    ctx.record_metric("max_neon_ratio", round(max_neon_ratio, 6))


def _check_t2_f05_shader_lighting_contracts(ctx: CheckContext) -> None:
    shaders_dir = ctx.project_dir / "src" / "presentation" / "shaders"
    hit_flash_path = shaders_dir / "actor_hit_flash.gdshader"
    ctx.assert_true(
        hit_flash_path.is_file(),
        "res://src/presentation/shaders/actor_hit_flash.gdshader exists",
    )
    if not hit_flash_path.is_file():
        return

    raw_src = hit_flash_path.read_text(encoding="utf-8")
    clean_src = _strip_shader_comments(raw_src)
    ctx.assert_str_contains(
        clean_src,
        "shader_type canvas_item;",
        "actor_hit_flash.gdshader declares 'shader_type canvas_item;'",
    )

    render_modes: list[str] = []
    for match in _RENDER_MODE_RE.finditer(clean_src):
        for tok in match.group(1).split(","):
            t = tok.strip()
            if t:
                render_modes.append(t)
    ctx.assert_false(
        "unshaded" in render_modes,
        "actor_hit_flash.gdshader MUST NOT declare render_mode unshaded (PointLight2D illumination contract)",
    )
    ctx.assert_true(
        bool(re.search(r"\buniform\s+float\b", clean_src)),
        "actor_hit_flash.gdshader exposes at least one 'uniform float' flash parameter",
    )

    all_shaders = sorted(shaders_dir.glob("*.gdshader"))
    for sh_path in all_shaders:
        sh_clean = _strip_shader_comments(sh_path.read_text(encoding="utf-8"))
        ctx.assert_str_contains(
            sh_clean,
            "shader_type canvas_item;",
            f"Shader '{sh_path.name}' declares 'shader_type canvas_item;'",
        )
        ctx.assert_false(
            "gl_FragColor" in sh_clean,
            f"Shader '{sh_path.name}' contains zero legacy GLSL gl_FragColor tokens",
        )

    ctx.record_metric("shader_count", len(all_shaders))
    ctx.record_metric("hit_flash_render_modes", render_modes)


def _check_t4_w1_master_b_reference_and_wcag(ctx: CheckContext) -> None:
    master_b = load_gate3_master(ctx.repo_root, "b")
    ctx.assert_eq(
        tuple(master_b.shape),
        (1080, 1920, 3),
        "Gate 3 master_b_cangmu_rtwp.png resolution is exact 1920x1080 RGB",
    )
    total_px = 1920 * 1080
    neon_px = count_fluorescent_pixels(master_b)
    neon_ratio = float(neon_px) / float(total_px)
    ctx.assert_lt(
        neon_ratio,
        0.002,
        "Gate 3 master_b_cangmu_rtwp.png has < 0.2% fluorescent neon pixels",
    )

    boss_roi = sample_roi_rgb_stats(master_b, (670, 14, 1250, 168))
    party_roi = sample_roi_rgb_stats(master_b, (16, 700, 425, 1068))
    bar_roi = sample_roi_rgb_stats(master_b, (430, 885, 1490, 1075))
    arena_roi = sample_roi_rgb_stats(master_b, (650, 360, 1450, 820))

    ctx.assert_gt(boss_roi["std_luma"], 18.0, "master_b top-center Boss plaque ROI has structured contrast")
    ctx.assert_gt(party_roi["std_luma"], 16.0, "master_b bottom-left F1~F3 party ROI has bust/bar contrast")
    ctx.assert_lt(bar_roi["mean_luma"], 95.0, "master_b bottom-center action bar uses dark-ebony mineral base")
    ctx.assert_gt(arena_roi["std_luma"], 22.0, "master_b Cangmu arena center ROI has rich figure/telegraph contrast")

    zh_map = _load_zh_cn_map(ctx.project_dir / "locales" / "zh_CN.csv")
    ctx.assert_eq(zh_map.get("TERM_HP", ""), "气血", "Canonical TERM_HP == '气血' (overrides raw 'HP')")
    ctx.assert_eq(zh_map.get("TERM_MP", ""), "真元", "Canonical TERM_MP == '真元' (overrides raw 'MP')")
    ctx.assert_eq(zh_map.get("TERM_WARD", ""), "护体灵罡", "Canonical TERM_WARD == '护体灵罡'")
    ctx.assert_eq(zh_map.get("TERM_ATTUNEMENT", ""), "同调气机", "Canonical TERM_ATTUNEMENT == '同调气机'")
    ctx.assert_true(bool(zh_map.get("HUD_TACTICAL_PAUSE", "")), "HUD_TACTICAL_PAUSE localized in zh_CN.csv")

    ebony_bg = (0x1C, 0x19, 0x17)
    xuan_warm = (0xE5, 0xDD, 0xD0)
    bronze_gold = (0xD6, 0xA8, 0x5A)
    contrast_xuan = wcag_contrast_ratio(xuan_warm, ebony_bg)
    contrast_gold = wcag_contrast_ratio(bronze_gold, ebony_bg)
    ctx.assert_ge(contrast_xuan, 10.0, "HUD Xuan-warm text on ebony background WCAG contrast >= 10.0:1")
    ctx.assert_ge(contrast_gold, 6.5, "HUD Bronze-gold title text on ebony background WCAG contrast >= 6.5:1")

    ctx.record_metric("master_b_neon_ratio", round(neon_ratio, 6))
    ctx.record_metric("hud_xuan_ebony_wcag", round(contrast_xuan, 2))
    ctx.record_metric("hud_gold_ebony_wcag", round(contrast_gold, 2))


def get_checks() -> list[dict[str, Any]]:
    return [
        make_check(
            "T1-F01-07",
            1,
            "F1",
            "baseline",
            "Combat JSON schema: 3-char skill bars, off-GCD Q interrupts, 30s pills, & 2-phase Boss skills",
            _check_t1_f01_data_contracts,
        ),
        make_check(
            "T1-F05-07",
            1,
            "F5",
            "polish_r1",
            "Polish R1 VFX/HUD textures & F1~F3 avatars + SHA-256 provenance in docs/asset-manifest.json",
            _check_t1_f05_polish_r1_assets_and_manifest,
        ),
        make_check(
            "T2-F05-07",
            2,
            "F5",
            "polish_r1",
            "Static shader lighting audit: actor_hit_flash.gdshader is shaded canvas_item WITHOUT unshaded",
            _check_t2_f05_shader_lighting_contracts,
        ),
        make_check(
            "T4-W1-04",
            4,
            "F5",
            "baseline",
            "Gate 3 master_b 1920x1080 Song-Ming mineral palette ROIs, <0.2% neon & zh_CN HUD WCAG contrast",
            _check_t4_w1_master_b_reference_and_wcag,
        ),
    ]
