"""Worker 2 (e2e_tw_2) Python E2E checks for F6 (Multi-Pose Actors/Boss), F7 (Portraits), and F15 (Manifest & Safety).

Covers:
- T1-F06-01 (polish_r2): Trio Song-Ming Gongbi multi-pose sprite sheet silhouettes & stride forensics.
- T1-F07-05 (polish_r2): 1024x1280 character portrait lossy .import & localized facial-feature residuals.
- T1-F15-06 (baseline):  manifest_guard.py --check 100% SHA-256 & provenance ledger verification.
- T2-F06-02 (polish_r2): Non-remap multi-pose provenance & zero baked PIL geometric rings/arcs.
- T2-F06-04 (baseline):  Sprite sheet lossless compress/mode=0 & 1px cell-border anti-clipping guard.
- T2-F15-04 (baseline):  Isolated scratch manifest_guard.py 5-subcase tamper detection.
- T2-F15-05 (baseline):  Zero scatter-popup class scan & sole SaveManager user://saves write guard.
"""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from PIL import Image

from tools.e2e import CheckContext, make_check
from tools.e2e.visual_master_inspector import (
    analyze_sprite_sheet_cells,
    compute_portrait_face_residual,
    count_fluorescent_pixels,
    load_rgba,
)

PARTY_SHEET_IDS: tuple[str, ...] = ("gu_changqing", "shen_qinghe", "pei_zhao")
ALL_R2_SHEET_IDS: tuple[str, ...] = (
    "gu_changqing",
    "shen_qinghe",
    "pei_zhao",
    "boss_mist_wolf_king",
)

PORTRAIT_EXPR_MATRIX: dict[str, tuple[str, ...]] = {
    "gu_changqing": (
        "calm",
        "cold",
        "guarded",
        "solemn",
        "smile_faint",
        "grief",
        "bloodied",
    ),
    "shen_qinghe": (
        "calm",
        "cold",
        "solemn",
        "smile_faint",
        "grief",
        "bloodied",
    ),
    "pei_zhao": (
        "calm",
        "cold",
        "solemn",
        "smile_faint",
        "grief",
        "bloodied",
    ),
    "mist_wolf_king": (
        "calm",
        "grief",
        "bloodied",
    ),
}

FORBIDDEN_POPUP_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("AcceptDialog", re.compile(r"\bAcceptDialog\b")),
    ("ConfirmationDialog", re.compile(r"\bConfirmationDialog\b")),
    ("FileDialog", re.compile(r"\bFileDialog\b")),
    ("PopupPanel", re.compile(r"\bPopupPanel\b")),
    ("PopupMenu", re.compile(r"\bPopupMenu\b")),
    ("PopupDialog", re.compile(r"\bPopupDialog\b")),
    ("Window.new", re.compile(r"\bWindow\s*\.\s*new\b")),
)


def _read_import_compress_mode(import_path: Path) -> int | None:
    if not import_path.is_file():
        return None
    for raw_line in import_path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()
        if line.startswith("compress/mode="):
            val = line.split("=", 1)[1].strip()
            if val.lstrip("-").isdigit():
                return int(val)
    return None


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _check_t1_f06_01_trio_multipose_sheets(ctx: CheckContext) -> None:
    """T1-F06-01: Trio multi-pose silhouettes, slash extension, down collapse & stride variation."""
    sprites_dir = ctx.project_dir / "assets" / "sprites"
    metrics_per_actor: dict[str, Any] = {}

    for sid in PARTY_SHEET_IDS:
        png_path = sprites_dir / f"{sid}_sheet.png"
        json_path = sprites_dir / f"{sid}_sheet.json"
        ctx.assert_true(png_path.is_file(), f"{sid}_sheet.png exists")
        ctx.assert_true(json_path.is_file(), f"{sid}_sheet.json exists")
        if not (png_path.is_file() and json_path.is_file()):
            continue

        report = analyze_sprite_sheet_cells(png_path, json_path, alpha_thresh=16)
        rows = report["rows"]
        for req_row in ("idle_se", "run_se", "attack_1", "attack_2", "cast_loop", "cast_release", "hit", "down"):
            ctx.assert_true(req_row in rows, f"{sid}_sheet.json defines row '{req_row}'")
        if not all(k in rows for k in ("idle_se", "run_se", "attack_1", "attack_2", "down")):
            continue

        idle_w = int(rows["idle_se"]["max_w"])
        idle_h = int(rows["idle_se"]["max_h"])
        atk_max_w = max(int(rows["attack_1"]["max_w"]), int(rows["attack_2"]["max_w"]))
        down_h = int(rows["down"]["max_h"])
        run_intra_iou = float(rows["run_se"]["intra_row_min_iou"])
        idle_atk_iou = float(report["pairwise_row_iou"].get("idle_se:attack_1", 1.0))

        ext_ratio = float(atk_max_w) / float(max(1, idle_w))
        down_ratio = float(down_h) / float(max(1, idle_h))
        metrics_per_actor[sid] = {
            "idle_w": idle_w,
            "idle_h": idle_h,
            "atk_max_w": atk_max_w,
            "ext_ratio": round(ext_ratio, 3),
            "down_h": down_h,
            "down_ratio": round(down_ratio, 3),
            "run_intra_iou": round(run_intra_iou, 3),
            "idle_atk_iou": round(idle_atk_iou, 3),
        }

        ctx.assert_true(
            132 <= idle_h <= 178,
            f"{sid} idle_se standing height {idle_h}px within 4.5-5.5 head scale [132..178px]",
        )
        ctx.assert_ge(
            ext_ratio,
            1.28,
            f"{sid} martial slash/thrust width ratio ({atk_max_w}/{idle_w}={ext_ratio:.3f}) >= 1.28x idle width",
        )
        ctx.assert_le(
            down_ratio,
            0.78,
            f"{sid} knockdown height ratio ({down_h}/{idle_h}={down_ratio:.3f}) <= 0.78x idle height",
        )
        ctx.assert_le(
            run_intra_iou,
            0.68,
            f"{sid} run_se alternating-leg stride min IoU ({run_intra_iou:.3f}) <= 0.68",
        )
        ctx.assert_le(
            idle_atk_iou,
            0.52,
            f"{sid} idle_se vs attack_1 centroid-aligned min IoU ({idle_atk_iou:.3f}) <= 0.52",
        )

    ctx.record_metric("trio_sheets", metrics_per_actor)


def _check_t1_f07_05_portrait_face_residuals(ctx: CheckContext) -> None:
    """T1-F07-05: 1024x1280 lossy .import & localized facial-feature residuals across 22 portraits."""
    portraits_dir = ctx.project_dir / "assets" / "portraits"
    ctx.assert_true(portraits_dir.is_dir(), "project/assets/portraits directory exists")

    guarded_path = portraits_dir / "gu_changqing_guarded.png"
    solemn_path = portraits_dir / "gu_changqing_solemn.png"
    if guarded_path.is_file() and solemn_path.is_file():
        sha_guarded = _sha256_bytes(guarded_path.read_bytes())
        sha_solemn = _sha256_bytes(solemn_path.read_bytes())
        ctx.assert_ne(
            sha_guarded,
            sha_solemn,
            "gu_changqing_guarded.png and gu_changqing_solemn.png must not be byte-identical duplicates",
        )

    residual_summary: dict[str, float] = {}
    checked_count = 0

    for pid, exprs in PORTRAIT_EXPR_MATRIX.items():
        calm_path = portraits_dir / f"{pid}_calm.png"
        ctx.assert_true(calm_path.is_file(), f"Base calm portrait {calm_path.name} exists")
        if not calm_path.is_file():
            continue

        for expr in exprs:
            p_path = portraits_dir / f"{pid}_{expr}.png"
            imp_path = portraits_dir / f"{pid}_{expr}.png.import"
            ctx.assert_true(p_path.is_file(), f"Portrait {p_path.name} exists")
            ctx.assert_true(imp_path.is_file(), f"Import file {imp_path.name} exists")
            if not p_path.is_file():
                continue

            checked_count += 1
            rgba = load_rgba(p_path)
            h, w = int(rgba.shape[0]), int(rgba.shape[1])
            ctx.assert_eq((w, h), (1024, 1280), f"{p_path.name} resolution is 1024x1280")

            cmode = _read_import_compress_mode(imp_path)
            ctx.assert_eq(cmode, 1, f"{imp_path.name} uses lossy VRAM-safe compress/mode=1")

            neon_px = count_fluorescent_pixels(rgba)
            ctx.assert_eq(neon_px, 0, f"{p_path.name} has 0 fluorescent neon pixels")

            if expr != "calm":
                res = compute_portrait_face_residual(calm_path, p_path)
                p99_res = float(res["p99_residual"])
                residual_summary[f"{pid}_{expr}"] = round(p99_res, 2)
                ctx.assert_ge(
                    p99_res,
                    12.0,
                    f"{p_path.name} localized face-ROI p99 residual ({p99_res:.2f}) >= 12.0 post-robe-tint fit",
                )

    ctx.assert_eq(checked_count, 22, "Verified all 22 canonical character & Wolf King portraits")
    ctx.record_metric("portrait_p99_residuals", residual_summary)


def _check_t1_f15_06_manifest_guard_pass(ctx: CheckContext) -> None:
    """T1-F15-06: Execute tools/manifest_guard.py --check on repository."""
    script_path = ctx.repo_root / "tools" / "manifest_guard.py"
    ctx.assert_true(script_path.is_file(), "tools/manifest_guard.py exists")

    proc = subprocess.run(
        [sys.executable, str(script_path), "--check"],
        cwd=str(ctx.repo_root),
        capture_output=True,
        text=True,
        timeout=60.0,
        check=False,
    )
    combined = (proc.stdout or "") + "\n" + (proc.stderr or "")
    ctx.assert_eq(proc.returncode, 0, f"manifest_guard.py --check exited 0 (out={combined.strip()})")
    ctx.assert_str_contains(
        proc.stdout,
        "Manifest OK:",
        "manifest_guard.py prints Manifest OK banner",
    )
    ctx.assert_str_contains(
        proc.stdout,
        "100% SHA-256 & provenance match.",
        "manifest_guard.py confirms 100% SHA-256 & provenance match",
    )

    m = re.search(r"Manifest OK:\s*(\d+)\s+registered assets", proc.stdout or "")
    asset_count = int(m.group(1)) if m else 0
    ctx.assert_gt(asset_count, 50, "manifest_guard.py verified > 50 registered project assets")
    ctx.record_metric("registered_assets", asset_count)


def _count_detached_or_thin_arc_components(
    rgba: np.ndarray,
    cell_w: int,
    cell_h: int,
    row_idx: int,
    col_idx: int,
) -> tuple[int, int]:
    """Count detached non-body components and thin outer-margin arc pixels in a sprite cell."""
    x0, y0 = col_idx * cell_w, row_idx * cell_h
    cell = rgba[y0 : y0 + cell_h, x0 : x0 + cell_w]
    mask = (cell[..., 3] >= 48).astype(np.uint8)
    n_comp, _, stats, _ = cv2.connectedComponentsWithStats(mask, connectivity=8)
    areas = sorted(
        (int(stats[i, cv2.CC_STAT_AREA]) for i in range(1, n_comp) if int(stats[i, cv2.CC_STAT_AREA]) >= 24),
        reverse=True,
    )
    detached_extra = max(0, len(areas) - 1)

    # Detect thin uniform-width geometric PIL strokes (thickness <= 9px) in outer right 22% margin
    outer_x = int(cell_w * 0.78)
    outer_mask = mask[:, outer_x:]
    thin_arc_cols = 0
    for cx in range(outer_mask.shape[1]):
        col_ys = np.nonzero(outer_mask[:, cx])[0]
        if len(col_ys) >= 2:
            span = int(col_ys[-1] - col_ys[0] + 1)
            fill_cnt = int(len(col_ys))
            # A pair of concentric PIL ImageDraw.arc strokes has two tiny vertical bands separated by a hollow gap
            if span >= 28 and fill_cnt <= 18:
                thin_arc_cols += 1
    return detached_extra, thin_arc_cols


def _check_t2_f06_02_no_remap_and_no_baked_pil_arcs(ctx: CheckContext) -> None:
    """T2-F06-02: Non-remap multi-pose sprite sheets & zero baked geometric PIL arcs/rings."""
    manifest_path = ctx.repo_root / "docs" / "asset-manifest.json"
    ctx.assert_true(manifest_path.is_file(), "docs/asset-manifest.json exists")
    doc = json.loads(manifest_path.read_text(encoding="utf-8"))
    by_path: dict[str, dict[str, Any]] = {
        str(e.get("path", "")): e for e in doc.get("assets", []) if isinstance(e, dict)
    }

    sprites_dir = ctx.project_dir / "assets" / "sprites"
    legacy_single_cutout_sources = {
        "assets_src/sprites/char_ref_party_pets_raw.jpg",
        "assets_src/sprites/char_ref_enemies_boss_raw.jpg",
    }

    diag: dict[str, Any] = {}
    for sid in ALL_R2_SHEET_IDS:
        rel_png = f"project/assets/sprites/{sid}_sheet.png"
        entry = by_path.get(rel_png, {})
        ctx.assert_true(bool(entry), f"Manifest contains entry for {rel_png}")
        method_str = str(entry.get("creation_method", ""))
        src_str = str(entry.get("source_path", ""))

        uses_legacy_single_remap = (
            ("build_step2_assets.py" in method_str)
            or ("build_r2_polish_assets.py" in method_str)
            or ("cv2.remap" in method_str)
            or (src_str in legacy_single_cutout_sources)
        )
        ctx.assert_false(
            uses_legacy_single_remap,
            f"{sid}_sheet.png must be built from genuine R2 multi-pose/skeletal sources, not single-cutout cv2.remap ({src_str})",
        )

        png_path = sprites_dir / f"{sid}_sheet.png"
        json_path = sprites_dir / f"{sid}_sheet.json"
        if not (png_path.is_file() and json_path.is_file()):
            continue

        report = analyze_sprite_sheet_cells(png_path, json_path, alpha_thresh=16)
        rgba = load_rgba(png_path)
        idle_cast_iou = float(report["pairwise_row_iou"].get("idle_se:cast_loop", 1.0))

        if sid in PARTY_SHEET_IDS:
            ctx.assert_le(
                idle_cast_iou,
                0.72,
                f"{sid} cast_loop must be a distinct hand-seal pose rather than 3px warped idle (IoU={idle_cast_iou:.3f} <= 0.72)",
            )
            det_atk, hollow_arc_cols = _count_detached_or_thin_arc_components(
                rgba, report["cell_w"], report["cell_h"], 4, 2
            )
            det_atk2, hollow_arc_cols2 = _count_detached_or_thin_arc_components(
                rgba, report["cell_w"], report["cell_h"], 5, 2
            )
            total_hollow_cols = hollow_arc_cols + hollow_arc_cols2
            diag[sid] = {
                "idle_cast_iou": round(idle_cast_iou, 3),
                "detached_components": det_atk + det_atk2,
                "hollow_pil_arc_cols": total_hollow_cols,
            }
            ctx.assert_le(
                total_hollow_cols,
                8,
                f"{sid} attack_1/attack_2 sprite cells must not contain baked hollow PIL ImageDraw.arc rings (hollow_cols={total_hollow_cols} <= 8; VFX belongs in CombatVfxOverlay)",
            )
        else:
            boss_idle_w = int(report["rows"]["idle_se"]["max_w"])
            boss_idle_h = int(report["rows"]["idle_se"]["max_h"])
            diag[sid] = {"boss_idle_w": boss_idle_w, "boss_idle_h": boss_idle_h}
            ctx.assert_ge(
                boss_idle_w,
                340,
                f"boss_mist_wolf_king sheet silhouette width ({boss_idle_w}px) >= 340px side-3/4 lunging body",
            )

    ctx.record_metric("r2_anti_remap_diag", diag)


def _check_t2_f06_04_sprite_import_and_cell_borders(ctx: CheckContext) -> None:
    """T2-F06-04: Lossless compress/mode=0 & 1px outer frame edge anti-clipping guard."""
    sprites_dir = ctx.project_dir / "assets" / "sprites"
    border_summary: dict[str, int] = {}

    for sid in ALL_R2_SHEET_IDS:
        png_path = sprites_dir / f"{sid}_sheet.png"
        imp_path = sprites_dir / f"{sid}_sheet.png.import"
        json_path = sprites_dir / f"{sid}_sheet.json"
        ctx.assert_true(png_path.is_file(), f"{png_path.name} exists")
        ctx.assert_true(imp_path.is_file(), f"{imp_path.name} exists")
        ctx.assert_true(json_path.is_file(), f"{json_path.name} exists")
        if not (png_path.is_file() and imp_path.is_file() and json_path.is_file()):
            continue

        cmode = _read_import_compress_mode(imp_path)
        ctx.assert_eq(
            cmode,
            0,
            f"{imp_path.name} uses lossless compress/mode=0 to preserve crisp Gongbi ink linework",
        )

        rgba = load_rgba(png_path)
        meta = json.loads(json_path.read_text(encoding="utf-8"))
        cw = int(meta.get("cell_w", 224))
        ch = int(meta.get("cell_h", 224))
        cols = int(meta.get("cols", 6))
        rows_def = dict(meta.get("rows", {}))
        max_row = max((int(r.get("row", 0)) for r in rows_def.values()), default=0)

        ctx.assert_ge(
            int(rgba.shape[1]),
            cols * cw,
            f"{png_path.name} width >= cols * cell_w ({cols * cw})",
        )
        ctx.assert_ge(
            int(rgba.shape[0]),
            (max_row + 1) * ch,
            f"{png_path.name} height >= (max_row + 1) * cell_h ({(max_row + 1) * ch})",
        )

        worst_lrt = 0
        for anim_name, rdef in rows_def.items():
            r_idx = int(rdef.get("row", 0))
            s_col = int(rdef.get("start_col", 0))
            f_cnt = int(rdef.get("frames", 1))
            for f_i in range(f_cnt):
                c_idx = s_col + f_i
                sub_a = rgba[r_idx * ch : (r_idx + 1) * ch, c_idx * cw : (c_idx + 1) * cw, 3]
                opaque_cnt = int((sub_a >= 16).sum())
                ctx.assert_ge(
                    opaque_cnt,
                    800,
                    f"{sid}:{anim_name}[{f_i}] has non-empty character pixels ({opaque_cnt} >= 800)",
                )
                hard_edge = sub_a > 64
                lrt = int(hard_edge[:, 0].sum() + hard_edge[:, -1].sum() + hard_edge[0, 1:-1].sum())
                worst_lrt = max(worst_lrt, lrt)
                ctx.assert_le(
                    lrt,
                    2,
                    f"{sid}:{anim_name}[{f_i}] left/right/top 1px cell edge opaque pixels ({lrt}) <= 2 (zero weapon/head clipping)",
                )
        border_summary[sid] = worst_lrt

    ctx.record_metric("max_lrt_border_px", border_summary)


def _check_t2_f15_04_manifest_guard_tamper_matrix(ctx: CheckContext) -> None:
    """T2-F15-04: Isolated scratch manifest_guard.py 5-subcase tamper detection."""
    fixture_root = ctx.scratch_dir / "manifest_tamper_fixture"
    ctx.assert_false(
        str(fixture_root).startswith("/tmp"),
        "Scratch fixture path must never reside under /tmp",
    )
    src_script = ctx.repo_root / "tools" / "manifest_guard.py"

    try:
        if fixture_root.exists():
            shutil.rmtree(fixture_root)
        (fixture_root / "tools").mkdir(parents=True, exist_ok=True)
        (fixture_root / "docs").mkdir(parents=True, exist_ok=True)
        (fixture_root / "project" / "assets" / "ui").mkdir(parents=True, exist_ok=True)
        (fixture_root / "assets_src" / "ui").mkdir(parents=True, exist_ok=True)

        dst_script = fixture_root / "tools" / "manifest_guard.py"
        shutil.copy2(src_script, dst_script)

        asset_file = fixture_root / "project" / "assets" / "ui" / "test_seal.png"
        raw_src_file = fixture_root / "assets_src" / "ui" / "test_seal_raw.png"
        manifest_file = fixture_root / "docs" / "asset-manifest.json"

        im = Image.new("RGBA", (32, 32), (62, 123, 103, 255))
        im.save(asset_file, format="PNG")
        im.save(raw_src_file, format="PNG")
        clean_bytes = asset_file.read_bytes()
        clean_sha = _sha256_bytes(clean_bytes)

        def write_manifest(sha_val: str, src_rel: str, lic_val: str) -> None:
            payload = {
                "schema_version": 1,
                "assets": [
                    {
                        "path": "project/assets/ui/test_seal.png",
                        "source_path": src_rel,
                        "creation_method": "Procedural PIL test fixture",
                        "license": lic_val,
                        "sha256": sha_val,
                        "dimensions": "32x32",
                    }
                ],
            }
            manifest_file.write_text(json.dumps(payload, indent=2), encoding="utf-8")

        def run_fixture() -> subprocess.CompletedProcess[str]:
            return subprocess.run(
                [sys.executable, str(dst_script), "--check"],
                cwd=str(fixture_root),
                capture_output=True,
                text=True,
                timeout=20.0,
                check=False,
            )

        # Subcase 0: Clean baseline -> exit 0
        write_manifest(clean_sha, "assets_src/ui/test_seal_raw.png", "CC0-1.0")
        r0 = run_fixture()
        ctx.assert_eq(r0.returncode, 0, "Subcase 0 (clean fixture) exits 0")
        ctx.assert_str_contains(r0.stdout, "Manifest OK: 1 registered assets", "Subcase 0 stdout")

        # Subcase 1: Flip byte in asset -> SHA-256 mismatch -> exit 1
        im_bad = Image.new("RGBA", (32, 32), (176, 58, 46, 255))
        im_bad.save(asset_file, format="PNG")
        r1 = run_fixture()
        ctx.assert_eq(r1.returncode, 1, "Subcase 1 (tampered PNG bytes) exits 1")
        ctx.assert_str_contains(r1.stderr, "SHA-256 mismatch", "Subcase 1 reports SHA-256 mismatch")
        asset_file.write_bytes(clean_bytes)

        # Subcase 2: Drop unrecorded rogue.png -> exit 1
        rogue_file = fixture_root / "project" / "assets" / "ui" / "rogue.png"
        im.save(rogue_file, format="PNG")
        r2 = run_fixture()
        ctx.assert_eq(r2.returncode, 1, "Subcase 2 (unrecorded rogue asset) exits 1")
        ctx.assert_str_contains(
            r2.stderr,
            "Unrecorded asset in project/assets/",
            "Subcase 2 reports Unrecorded asset",
        )
        rogue_file.unlink()

        # Subcase 3: Remove assets_src provenance file -> exit 1
        raw_src_file.unlink()
        r3 = run_fixture()
        ctx.assert_eq(r3.returncode, 1, "Subcase 3 (missing assets_src file) exits 1")
        ctx.assert_str_contains(
            r3.stderr,
            "Missing assets_src provenance file",
            "Subcase 3 reports Missing assets_src provenance file",
        )
        im.save(raw_src_file, format="PNG")

        # Subcase 4: Set license to Unrecorded -> exit 1
        write_manifest(clean_sha, "assets_src/ui/test_seal_raw.png", "Unrecorded")
        r4 = run_fixture()
        ctx.assert_eq(r4.returncode, 1, "Subcase 4 (Unrecorded license) exits 1")
        ctx.assert_str_contains(
            r4.stderr,
            "Missing valid license",
            "Subcase 4 reports Missing valid license",
        )
    finally:
        if fixture_root.exists():
            shutil.rmtree(fixture_root, ignore_errors=True)


def _check_t2_f15_05_no_scatter_popups_and_sole_save_writer(ctx: CheckContext) -> None:
    """T2-F15-05: Zero unauthorized popup classes & sole SaveManager user://saves guard."""
    src_root = ctx.project_dir / "src"
    ctx.assert_true(src_root.is_dir(), "project/src directory exists")

    popup_offenders: list[str] = []
    save_dir_offenders: list[str] = []
    scanned_files = 0

    for gd_path in sorted(src_root.rglob("*.gd")):
        scanned_files += 1
        rel = gd_path.relative_to(ctx.repo_root).as_posix()
        lines = gd_path.read_text(encoding="utf-8", errors="replace").splitlines()
        for lineno, raw_line in enumerate(lines, start=1):
            code_only = raw_line.split("#", 1)[0]
            if not code_only.strip():
                continue
            for label, pat in FORBIDDEN_POPUP_PATTERNS:
                if pat.search(code_only):
                    popup_offenders.append(f"{rel}:{lineno} ({label})")
            if "user://saves" in code_only and gd_path.name != "save_manager.gd":
                save_dir_offenders.append(f"{rel}:{lineno}")

    for tscn_path in sorted(src_root.rglob("*.tscn")):
        scanned_files += 1
        rel = tscn_path.relative_to(ctx.repo_root).as_posix()
        text = tscn_path.read_text(encoding="utf-8", errors="replace")
        for label, pat in FORBIDDEN_POPUP_PATTERNS:
            if pat.search(text):
                popup_offenders.append(f"{rel} ({label})")

    ctx.assert_gt(scanned_files, 15, "Scanned all GDScript & scene files under project/src")
    ctx.assert_eq(
        popup_offenders,
        [],
        "Zero scatter-popup classes (AcceptDialog/ConfirmationDialog/FileDialog/PopupPanel/Window.new) in project/src",
    )
    ctx.assert_eq(
        save_dir_offenders,
        [],
        "save_manager.gd is the sole module referencing user://saves",
    )
    ctx.record_metric("scanned_src_files", scanned_files)


def get_checks() -> list[dict[str, Any]]:
    return [
        make_check(
            "T1-F06-01",
            1,
            "F6",
            "polish_r2",
            "Trio Song-Ming Gongbi multi-pose sprite sheet silhouettes, slash span & stride variation",
            _check_t1_f06_01_trio_multipose_sheets,
        ),
        make_check(
            "T1-F07-05",
            1,
            "F7",
            "polish_r2",
            "Character & Boss 1024x1280 portrait lossy .import & localized facial-feature residuals",
            _check_t1_f07_05_portrait_face_residuals,
        ),
        make_check(
            "T1-F15-06",
            1,
            "F15",
            "baseline",
            "Asset manifest ledger 100% SHA-256, assets_src provenance & license verification",
            _check_t1_f15_06_manifest_guard_pass,
        ),
        make_check(
            "T2-F06-02",
            2,
            "F6",
            "polish_r2",
            "Round 2 sprite sheets eliminate single-cutout cv2.remap warp & baked PIL geometric arcs",
            _check_t2_f06_02_no_remap_and_no_baked_pil_arcs,
        ),
        make_check(
            "T2-F06-04",
            2,
            "F6",
            "baseline",
            "Sprite sheet lossless compress/mode=0 & 1px cell boundary anti-clipping guard",
            _check_t2_f06_04_sprite_import_and_cell_borders,
        ),
        make_check(
            "T2-F15-04",
            2,
            "F15",
            "baseline",
            "Isolated scratch manifest_guard.py 5-subcase tamper detection matrix",
            _check_t2_f15_04_manifest_guard_tamper_matrix,
        ),
        make_check(
            "T2-F15-05",
            2,
            "F15",
            "baseline",
            "Zero unauthorized popup classes & sole SaveManager user://saves write enforcement",
            _check_t2_f15_05_no_scatter_popups_and_sole_save_writer,
        ),
    ]
