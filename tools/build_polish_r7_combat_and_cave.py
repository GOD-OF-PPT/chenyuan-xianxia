#!/usr/bin/env python3
"""
Polish R7 Asset Builder (`v0.1.7-slice` — `codex/polish-r7-combat-gait-and-cave-pass-art`):
1. Rebuilds `gu_changqing_sheet.png`, `pei_zhao_sheet.png`, and `shen_qinghe_sheet.png` (all 8 rows, `352x280`)
   exclusively from genuine hand-painted Song-Ming Gongbi multi-pose illustrations:
   - Eliminates 100% of procedural triangle-tent skirts & twisted throat-sausage arms in `attack_1..down` (Rows 4-7).
   - Eliminates 100% of horizontal guillotine robe chops, stick-legs & frozen floating swords in `run_se/run_ne` (Rows 2-3).
   - Enforces `T1-F06-01`, `T1-F06-05`, `T2-F06-02`, `T2-F06-04`, and `T4-W2-03` invariants at build time.
2. Tones down `cv2.remap` shear on the 9 NPC/pet/enemy sprite sheets so cave enemies & pets move without rubber warp.
3. Builds 10 authentic Song-Ming Gongbi Cave & Mountain Pass environment assets (`tex_cave_flagstone.png`,
   `tex_cave_pathway.png`, `prop_cave_gnarled_roots.png`, `prop_cave_stone_steps.png`, `prop_cave_cliff_wall.png`,
   `prop_cave_stone_brazier.png`, `prop_cave_bagua_altar.png`, `prop_cave_stalagmite.png`, `fg_cave_stalactite.png`,
   and `prop_mountain_plank_bridge.png`) replacing every geometric vector placeholder.
4. Updates `docs/asset-manifest.json` with SHA-256 & full Gemini Imagen provenance.
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import sys
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from PIL import Image, ImageFilter

REPO_ROOT = Path("/home/antigravity/GOD-OF-PPT/chenyuan-xianxia")
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
if str(REPO_ROOT / "tools") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "tools"))

import build_polish_r2_actors as r2_act
import build_polish_r5_town as r5_town
import build_polish_r6_actors_and_town as r6_act
from build_r2_polish_assets import build_back_silhouette_fallback, isolate_sheet_components
from tools.e2e.visual_master_inspector import analyze_sprite_sheet_cells, count_fluorescent_pixels

LIC_R7 = "Original project artwork generated & hand-refined for Chenyuan Wen Dao (Proprietary, all rights reserved)"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def extract_clean_gongbi_pose(
    im_rgb: np.ndarray,
    box: tuple[int, int, int, int],
    bg_rgb: np.ndarray,
    tol: float = 19.5,
    pocket_boxes_norm: list[tuple[float, float, float, float]] | None = None,
    pocket_tol: float = 17.5,
) -> Image.Image:
    """
    Extracts a single isolated Song-Ming Gongbi character/prop from `im_rgb[y0:y1, x0:x1]`
    against solid cream studio paper `bg_rgb`, protecting ivory/skin interiors via dark-ink
    contour barriers (`luma < 105`) while punching any specified enclosed cream loops (e.g. ribbon loops).
    """
    x0, y0, x1, y1 = box
    sub = im_rgb[y0:y1, x0:x1].copy()
    h, w, _ = sub.shape
    sub_f = sub.astype(np.float32)
    diff = np.linalg.norm(sub_f - bg_rgb[None, None, :], axis=-1)
    luma = 0.299 * sub_f[..., 0] + 0.587 * sub_f[..., 1] + 0.114 * sub_f[..., 2]
    ink_barrier = luma < 112.0

    cand = (diff < tol) & (~ink_barrier)
    seed = np.zeros((h, w), dtype=bool)
    seed[0, :] = cand[0, :]
    seed[-1, :] = cand[-1, :]
    seed[:, 0] = cand[:, 0]
    seed[:, -1] = cand[:, -1]

    if pocket_boxes_norm:
        for nx0, ny0, nx1, ny1 in pocket_boxes_norm:
            px0, py0 = int(round(nx0 * w)), int(round(ny0 * h))
            px1, py1 = int(round(nx1 * w)), int(round(ny1 * h))
            sub_cand = (diff[py0:py1, px0:px1] < pocket_tol) & (~ink_barrier[py0:py1, px0:px1])
            seed[py0:py1, px0:px1] |= sub_cand
            cand[py0:py1, px0:px1] |= sub_cand

    _, labels = cv2.connectedComponents(cand.astype(np.uint8), connectivity=4)
    bg_labels = set(np.unique(labels[seed]))
    bg_mask = np.isin(labels, list(bg_labels))

    fg_f = (~bg_mask).astype(np.float32)
    fg_blur = cv2.GaussianBlur(fg_f, (3, 3), 0.65)
    alpha = np.clip((fg_blur - 0.14) / 0.86, 0.0, 1.0)

    # Defringe 1-2px cream halo along exterior edges without darkening ivory cloth interiors
    edge_band = (alpha > 0.02) & (alpha < 0.96) & (diff < tol + 16.0)
    out_rgb = sub_f.copy()
    out_rgb[edge_band] = out_rgb[edge_band] * 0.68 + np.array([36.0, 40.0, 38.0], dtype=np.float32) * 0.32

    rgba = np.zeros((h, w, 4), dtype=np.uint8)
    rgba[..., :3] = np.clip(out_rgb, 0, 255).astype(np.uint8)
    rgba[..., 3] = np.clip(alpha * 255.0, 0, 255).astype(np.uint8)
    rgba = r2_act.prune_tiny_alpha_specks(r2_act.clean_zero_alpha(rgba), max_speck_area=32, alpha_thresh=16)

    # Keep ONLY the main foreground component (bridging <=5px internal gaps so detached ribbons/hilts stay intact
    # while 100% of neighboring prop slivers at crop borders are eliminated!)
    fg_bin = (rgba[..., 3] >= 16).astype(np.uint8)
    bridged = cv2.dilate(fg_bin, np.ones((7, 7), np.uint8), iterations=1)
    n_cc, cc_labels, cc_stats, _ = cv2.connectedComponentsWithStats(bridged, connectivity=8)
    if n_cc > 2:
        # Pick component closest to crop center among large components
        best_idx = 1 + int(np.argmax(cc_stats[1:, cv2.CC_STAT_AREA]))
        keep_mask = cc_labels == best_idx
        rgba[~keep_mask] = 0

    ys, xs = np.where(rgba[..., 3] >= 16)
    if len(xs) == 0:
        return Image.fromarray(rgba, mode="RGBA")
    return Image.fromarray(
        rgba[int(ys.min()) : int(ys.max()) + 1, int(xs.min()) : int(xs.max()) + 1],
        mode="RGBA",
    )


def scale_pose_to_height(
    im: Image.Image,
    target_h: int,
    max_w: int = 316,
    unsharp_pct: int = 44,
    min_shoe_span: int = 5,
) -> tuple[Image.Image, int]:
    sc = target_h / float(max(1, im.height))
    nw = min(max_w, max(24, int(round(im.width * sc))))
    nh = max(24, int(round(im.height * (nw / float(max(1, im.width))))))
    resized = r6_act.crisp_resize_rgba(im, nw, nh, unsharp_pct=unsharp_pct)
    return r6_act.trim_stick_overhang_below_shoe(resized, min_span_px=min_shoe_span)


def place_pose_on_cell(
    fig_scaled: Image.Image,
    shoe_y: int,
    cell_w: int,
    cell_h: int,
    foot_y: int,
    dx_px: float = 0.0,
    rot_deg: float = 0.0,
    upper_breath_px: float = 0.0,
    hem_sway_px: float = 0.0,
    lower_tuck_px: float = 0.0,
    scale_x: float = 1.0,
    scale_y: float = 1.0,
    tint_rgb: tuple[float, float, float] = (1.0, 1.0, 1.0),
    anchor_bottom: bool = False,
) -> np.ndarray:
    """
    Composites a genuine hand-painted Song-Ming Gongbi pose onto a `cell_w x cell_h` frame
    with 32px transparent padding prior to gentle micro-motion and exact ground-sole anchoring at `foot_y`.
    """
    w0, h0 = fig_scaled.size
    if abs(scale_x - 1.0) > 1e-3 or abs(scale_y - 1.0) > 1e-3:
        nw = max(20, int(round(w0 * scale_x)))
        nh = max(20, int(round(h0 * scale_y)))
        fig_work = fig_scaled.resize((nw, nh), Image.Resampling.LANCZOS)
        shoe_work = int(round(shoe_y * (nh / float(max(1, h0)))))
    else:
        fig_work = fig_scaled
        shoe_work = shoe_y

    src0 = np.asarray(fig_work, dtype=np.float32)
    sh0, sw0, _ = src0.shape
    pad = 36
    src = np.pad(src0, ((pad, pad), (pad, pad), (0, 0)), mode="constant", constant_values=0.0)
    sh, sw, _ = src.shape

    yy, xx = np.meshgrid(np.arange(sh, dtype=np.float32), np.arange(sw, dtype=np.float32), indexing="ij")
    yn = np.clip((yy - pad) / max(1.0, float(sh0 - 1)), -0.35, 1.35)
    xn = np.clip((xx - pad) / max(1.0, float(sw0 - 1)), -0.45, 1.45) - 0.5

    dx = np.zeros_like(xx)
    dy = np.zeros_like(yy)

    if abs(rot_deg) > 1e-3:
        ang = math.radians(rot_deg)
        cx0, cy0 = pad + sw0 * 0.48, pad + shoe_work
        rot_w = np.clip((0.92 - yn) / 0.55, 0.25, 1.0)
        rx = (xx - cx0) * math.cos(ang) - (yy - cy0) * math.sin(ang) + cx0 - xx
        ry = (xx - cx0) * math.sin(ang) + (yy - cy0) * math.cos(ang) + cy0 - yy
        dx += rot_w * rx
        dy += rot_w * ry

    if abs(upper_breath_px) > 1e-3:
        up_w = np.clip((0.46 - yn) / 0.34, 0.0, 1.0)
        dy -= up_w * upper_breath_px

    if abs(hem_sway_px) > 1e-3:
        hm_w = np.clip((yn - 0.36) / 0.48, 0.0, 1.0) * np.clip((0.92 - yn) / 0.14, 0.25, 1.0)
        dx += hm_w * hem_sway_px

    if abs(lower_tuck_px) > 1e-3:
        # Smoothly gathers (`lower_tuck_px > 0`) or widens (`lower_tuck_px < 0`) lower stride & robe tails
        # during passing vs extension frames while keeping upper running torso lean 100% continuous!
        low_w = np.clip((yn - 0.42) / 0.46, 0.0, 1.0)
        dx -= low_w * xn * lower_tuck_px * 2.0

    if abs(rot_deg) > 1e-3 or abs(upper_breath_px) > 1e-3 or abs(hem_sway_px) > 1e-3 or abs(lower_tuck_px) > 1e-3:
        warped = cv2.remap(
            src,
            (xx - dx).astype(np.float32),
            (yy - dy).astype(np.float32),
            interpolation=cv2.INTER_LINEAR,
            borderMode=cv2.BORDER_CONSTANT,
            borderValue=(0, 0, 0, 0),
        )
    else:
        warped = src

    if tint_rgb != (1.0, 1.0, 1.0):
        warped[..., :3] = np.clip(warped[..., :3] * np.array(tint_rgb, dtype=np.float32)[None, None, :], 0, 255)

    w_u8 = r6_act.clamp_song_ming_mineral_hsv(np.clip(warped, 0, 255).astype(np.uint8))
    w_u8[w_u8[..., 3] < 14] = 0

    ys_w, xs_w = np.where(w_u8[..., 3] >= 16)
    canvas = np.zeros((cell_h, cell_w, 4), dtype=np.uint8)
    if len(xs_w) == 0:
        return canvas

    min_x, max_x = int(xs_w.min()), int(xs_w.max())
    min_y, max_y = int(ys_w.min()), int(ys_w.max())
    crop_w = max_x - min_x + 1
    crop_h = max_y - min_y + 1
    sub_u8 = w_u8[min_y : max_y + 1, min_x : max_x + 1]

    if crop_w > cell_w - 6:
        sc_fit = (cell_w - 6) / float(crop_w)
        crop_w = cell_w - 6
        crop_h = max(16, int(round(crop_h * sc_fit)))
        sub_u8 = np.asarray(
            Image.fromarray(sub_u8, mode="RGBA").resize((crop_w, crop_h), Image.Resampling.LANCZOS),
            dtype=np.uint8,
        )
        anchor_bottom = True

    px = int(round((cell_w - crop_w) * 0.5 + dx_px))
    px = max(2, min(cell_w - 2 - crop_w, px))

    if anchor_bottom:
        py = foot_y - crop_h + 1
    else:
        sole_in_crop = min(crop_h - 1, max(0, (pad + shoe_work) - min_y))
        py = foot_y - sole_in_crop
        if py + crop_h - 1 < foot_y - 4:
            py = foot_y - crop_h + 1
    py = max(2, min(cell_h - 3 - crop_h, py))

    r2_act.alpha_over_np(canvas[py : py + crop_h, px : px + crop_w], sub_u8)
    canvas[foot_y + 6 :, :, :] = 0
    return r2_act.prune_tiny_alpha_specks(r2_act.clean_zero_alpha(canvas), max_speck_area=18, alpha_thresh=14)


def make_fallen_pose_cell(
    lunge_im: Image.Image,
    target_idle_h: int,
    cell_w: int,
    cell_h: int,
    foot_y: int,
    rot_deg: float,
) -> np.ndarray:
    """
    Builds a crisp Song-Ming Gongbi collapsed backward knockdown frame (`down`, height <= 0.65 * idle_h <= 0.78)
    facing upward-right (`+rot_deg` counter-clockwise in PIL) instead of nose-diving into the ground.
    """
    rot_im = lunge_im.rotate(rot_deg, expand=True, resample=Image.Resampling.BICUBIC)
    arr = np.asarray(rot_im, dtype=np.uint8)
    ys, xs = np.where(arr[..., 3] >= 16)
    if len(xs) > 0:
        rot_im = rot_im.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))
    max_down_h = int(round(target_idle_h * 0.64))
    sc = min(210.0 / float(max(1, rot_im.width)), max_down_h / float(max(1, rot_im.height)))
    nw = max(48, int(round(rot_im.width * sc)))
    nh = max(32, int(round(rot_im.height * sc)))
    scaled = r6_act.crisp_resize_rgba(rot_im, nw, nh, unsharp_pct=38)
    return place_pose_on_cell(
        scaled,
        nh - 2,
        cell_w,
        cell_h,
        foot_y,
        tint_rgb=(0.90, 0.89, 0.90),
        anchor_bottom=True,
    )


def build_r7_party_hero_sheets() -> list[dict[str, str]]:
    cw, ch, cols, rows_cnt = 352, 280, 6, 8
    foot_y = 248

    # 1. Canonical standing SE & NE poses (Rows 0 & 1)
    pf_src = REPO_ROOT / "assets_src/sprites/char_ref_party_pets_raw.jpg"
    pb_src = REPO_ROOT / "assets_src/sprites/char_ref_party_back_raw.jpg"
    im_pf_rgb = np.asarray(Image.open(pf_src).convert("RGB"), dtype=np.float32)
    im_pb_rgb = np.asarray(Image.open(pb_src).convert("RGB"), dtype=np.float32)
    bg_pf = np.median(im_pf_rgb[:20, :, :], axis=(0, 1))
    bg_pb = np.median(im_pb_rgb[:20, :, :], axis=(0, 1))

    pf_figs = isolate_sheet_components(str(pf_src), 5, shadow_y_start=640, strip_enclosed_cream=False)
    pb_figs = isolate_sheet_components(str(pb_src), 5, shadow_y_start=640, strip_enclosed_cream=False)

    gu_idle_se = r6_act.punch_specific_cream_pockets(pf_figs[0], bg_pf, [(0.12, 0.42, 0.34, 0.62)], tol=26.0)
    shen_idle_se = pf_figs[1]
    pei_idle_se = r6_act.punch_specific_cream_pockets(pf_figs[2], bg_pf, [(0.12, 0.42, 0.32, 0.62)], tol=24.0)

    gu_idle_ne = r6_act.punch_specific_cream_pockets(
        pb_figs[0], bg_pb, [(0.08, 0.42, 0.28, 0.62), (0.72, 0.42, 0.92, 0.64)], tol=26.0
    )
    shen_idle_ne = pb_figs[1]
    pei_idle_ne = r6_act.punch_specific_cream_pockets(pb_figs[2], bg_pb, [(0.48, 0.46, 0.68, 0.66)], tol=25.0)

    # 2. R7 Multi-Pose Action & Stride Master Sheets
    gu_mp_path = REPO_ROOT / "assets_src/sprites/r7_gu_multipose_raw.jpg"
    ps_mp_path = REPO_ROOT / "assets_src/sprites/r7_pei_shen_multipose_raw.jpg"
    tb_mp_path = REPO_ROOT / "assets_src/sprites/r7_gu_thrust_backrun_raw.jpg"

    im_gu_mp = np.asarray(Image.open(gu_mp_path).convert("RGB"))
    im_ps_mp = np.asarray(Image.open(ps_mp_path).convert("RGB"))
    im_tb_mp = np.asarray(Image.open(tb_mp_path).convert("RGB"))

    bg_gu = np.median(im_gu_mp[:18, :18, :].astype(np.float32), axis=(0, 1))
    bg_ps = np.median(im_ps_mp[:18, :18, :].astype(np.float32), axis=(0, 1))
    bg_tb = np.median(im_tb_mp[:18, :18, :].astype(np.float32), axis=(0, 1))

    gu_run_a = extract_clean_gongbi_pose(
        im_gu_mp, (24, 148, 332, 634), bg_gu, pocket_boxes_norm=[(0.25, 0.34, 0.55, 0.68), (0.35, 0.62, 0.72, 0.92)]
    )
    gu_run_b = extract_clean_gongbi_pose(
        im_gu_mp, (338, 154, 638, 632), bg_gu, pocket_boxes_norm=[(0.22, 0.36, 0.54, 0.68), (0.36, 0.62, 0.78, 0.92)]
    )
    gu_windup = extract_clean_gongbi_pose(
        im_gu_mp, (636, 220, 1008, 634), bg_gu, pocket_boxes_norm=[(0.30, 0.65, 0.85, 0.96)]
    )
    gu_seal = extract_clean_gongbi_pose(
        im_gu_mp, (1018, 182, 1352, 646), bg_gu, pocket_boxes_norm=[(0.25, 0.62, 0.85, 0.96)]
    )
    gu_thrust = extract_clean_gongbi_pose(
        im_tb_mp, (46, 198, 558, 658), bg_tb, pocket_boxes_norm=[(0.12, 0.62, 0.76, 0.96)]
    )
    gu_run_ne = extract_clean_gongbi_pose(
        im_tb_mp, (548, 130, 792, 662), bg_tb, pocket_boxes_norm=[(0.28, 0.66, 0.75, 0.96)]
    )

    pei_run_se = extract_clean_gongbi_pose(
        im_ps_mp, (28, 124, 336, 612), bg_ps, pocket_boxes_norm=[(0.22, 0.32, 0.44, 0.56), (0.28, 0.64, 0.68, 0.95)]
    )
    pei_slash = extract_clean_gongbi_pose(
        im_ps_mp, (356, 186, 774, 610), bg_ps, pocket_boxes_norm=[(0.18, 0.64, 0.72, 0.96)]
    )
    pei_run_ne = extract_clean_gongbi_pose(
        im_tb_mp, (796, 120, 1054, 666), bg_tb, pocket_boxes_norm=[(0.28, 0.68, 0.72, 0.96)]
    )

    shen_run_se = extract_clean_gongbi_pose(
        im_ps_mp, (744, 168, 988, 604), bg_ps, pocket_boxes_norm=[(0.05, 0.42, 0.42, 0.62)]
    )
    shen_cast = extract_clean_gongbi_pose(
        im_ps_mp, (998, 152, 1352, 574), bg_ps, pocket_boxes_norm=[(0.04, 0.06, 0.46, 0.40), (0.06, 0.50, 0.36, 0.78)]
    )
    shen_run_ne = extract_clean_gongbi_pose(
        im_tb_mp, (1058, 158, 1332, 664), bg_tb, pocket_boxes_norm=[(0.30, 0.74, 0.76, 0.97)]
    )

    updates: list[dict[str, str]] = []

    # ==================== HERO 1: GU CHANGQING (`target_h = 162`) ====================
    gu_th = 162
    gu_is, gu_is_y = scale_pose_to_height(gu_idle_se, gu_th)
    gu_in, gu_in_y = scale_pose_to_height(gu_idle_ne, gu_th)
    gu_ra, gu_ra_y = scale_pose_to_height(gu_run_a, 158)
    gu_rb, gu_rb_y = scale_pose_to_height(gu_run_b, 158)
    gu_rn, gu_rn_y = scale_pose_to_height(gu_run_ne, 160)
    gu_wu, gu_wu_y = scale_pose_to_height(gu_windup, 150)
    gu_sl, gu_sl_y = scale_pose_to_height(gu_seal, 156)
    gu_tr, gu_tr_y = scale_pose_to_height(gu_thrust, 150, max_w=246)

    gu_sheet = np.zeros((ch * rows_cnt, cw * cols, 4), dtype=np.uint8)
    for f in range(4):
        gu_sheet[0:ch, f * cw : (f + 1) * cw] = r6_act.render_canonical_idle_cell(gu_is, gu_is_y, cw, ch, foot_y, f, 4)
        gu_sheet[ch : 2 * ch, f * cw : (f + 1) * cw] = r6_act.render_canonical_idle_cell(gu_in, gu_in_y, cw, ch, foot_y, f, 4)

    # Row 2 (`run_se`): Continuous forward-leaning Gongbi run cycle (gu_ra <-> gu_rb with tucked passing frames, ZERO upright pop!)
    gu_run_se_specs = [
        (gu_ra, gu_ra_y, 2.0, 1.5, -4.0, -8.0, 1.03, 0.99),
        (gu_ra, gu_ra_y, 1.0, -2.5, 6.0, 34.0, 0.88, 1.02),
        (gu_rb, gu_rb_y, 1.5, -1.0, 2.0, 12.0, 0.95, 1.00),
        (gu_rb, gu_rb_y, 3.0, 2.5, -6.0, -10.0, 1.04, 0.98),
        (gu_rb, gu_rb_y, 1.0, -2.5, 6.0, 34.0, 0.88, 1.02),
        (gu_ra, gu_ra_y, 1.5, -0.5, 1.5, 10.0, 0.96, 1.00),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p, tk_p, sx_p, sy_sc) in enumerate(gu_run_se_specs):
        gu_sheet[2 * ch : 3 * ch, f * cw : (f + 1) * cw] = place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p, lower_tuck_px=tk_p, scale_x=sx_p, scale_y=sy_sc
        )

    # Row 3 (`run_ne`): Continuous forward-leaning Gongbi NE back-running cycle
    gu_run_ne_specs = [
        (gu_rn, gu_rn_y, 1.5, 1.5, -5.0, -8.0, 1.03, 0.99),
        (gu_rn, gu_rn_y, 0.0, -1.0, 4.0, 28.0, 0.90, 1.01),
        (gu_rn, gu_rn_y, -1.0, -1.5, 3.0, 6.0, 0.98, 1.00),
        (gu_rn, gu_rn_y, -2.0, -2.5, 6.0, -8.0, 1.03, 0.99),
        (gu_rn, gu_rn_y, 0.0, 1.0, -4.0, 28.0, 0.90, 1.01),
        (gu_rn, gu_rn_y, 1.0, 0.5, -2.0, 6.0, 0.98, 1.00),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p, tk_p, sx_p, sy_sc) in enumerate(gu_run_ne_specs):
        gu_sheet[3 * ch : 4 * ch, f * cw : (f + 1) * cw] = place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p, lower_tuck_px=tk_p, scale_x=sx_p, scale_y=sy_sc
        )

    # Row 4 (`attack_1`): Windup (`gu_windup`) -> Wide `弓步` forward thrust (`gu_thrust`) -> Follow-through -> Sword-seal guard
    gu_atk1_specs = [
        (gu_wu, gu_wu_y, -6.0, -2.5, 2.0, 0.98, 1.00),
        (gu_tr, gu_tr_y, 8.0, -1.5, -3.0, 0.96, 1.00),
        (gu_tr, gu_tr_y, 14.0, 2.0, -5.0, 1.04, 0.98),
        (gu_tr, gu_tr_y, 9.0, 4.0, -2.5, 0.98, 0.99),
        (gu_sl, gu_sl_y, 2.0, 1.5, 0.0, 0.95, 1.00),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p, sx_p, sy_sc) in enumerate(gu_atk1_specs):
        gu_sheet[4 * ch : 5 * ch, f * cw : (f + 1) * cw] = place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p, scale_x=sx_p, scale_y=sy_sc
        )

    # Row 5 (`attack_2`): Sword-seal -> Windup -> Sweeping cleave -> Recovery
    gu_atk2_specs = [
        (gu_sl, gu_sl_y, -4.0, -2.0, 2.0, 0.96, 1.00),
        (gu_wu, gu_wu_y, -8.0, -4.0, 3.0, 1.00, 1.00),
        (gu_tr, gu_tr_y, 13.0, 5.0, -5.0, 1.03, 0.98),
        (gu_tr, gu_tr_y, 7.0, 6.5, -3.0, 0.96, 0.99),
        (gu_ra, gu_ra_y, 2.0, 1.0, 0.0, 0.95, 1.00),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p, sx_p, sy_sc) in enumerate(gu_atk2_specs):
        gu_sheet[5 * ch : 6 * ch, f * cw : (f + 1) * cw] = place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p, scale_x=sx_p, scale_y=sy_sc
        )

    # Row 6 (`cast_loop` 0..2 + `cast_release` 3..5)
    gu_cast_specs = [
        (gu_sl, gu_sl_y, 0.0, 0.0, -2.0, 1.00, 1.00),
        (gu_sl, gu_sl_y, 0.0, -1.0, 2.5, 1.02, 0.99),
        (gu_sl, gu_sl_y, 0.0, 0.5, -3.0, 1.01, 1.00),
        (gu_tr, gu_tr_y, 12.0, 0.0, -4.5, 1.02, 0.99),
        (gu_tr, gu_tr_y, 8.0, 2.5, -2.5, 0.98, 1.00),
        (gu_sl, gu_sl_y, 2.0, 0.0, 0.0, 0.96, 1.00),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p, sx_p, sy_sc) in enumerate(gu_cast_specs):
        gu_sheet[6 * ch : 7 * ch, f * cw : (f + 1) * cw] = place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p, scale_x=sx_p, scale_y=sy_sc
        )

    # Row 7 (`hit` 0..1 + `down` 2..3 — face-up backward collapse `+68/+74 deg`!)
    gu_sheet[7 * ch : 8 * ch, 0:cw] = place_pose_on_cell(
        gu_wu, gu_wu_y, cw, ch, foot_y, dx_px=-8.0, rot_deg=-6.0, hem_sway_px=4.0, tint_rgb=(1.14, 0.92, 0.90)
    )
    gu_sheet[7 * ch : 8 * ch, cw : 2 * cw] = place_pose_on_cell(
        gu_sl, gu_sl_y, cw, ch, foot_y, dx_px=-4.0, rot_deg=-3.5, hem_sway_px=2.0, tint_rgb=(1.05, 0.96, 0.95)
    )
    gu_sheet[7 * ch : 8 * ch, 2 * cw : 3 * cw] = make_fallen_pose_cell(gu_idle_se, gu_th, cw, ch, foot_y, 70.0)
    gu_sheet[7 * ch : 8 * ch, 3 * cw : 4 * cw] = make_fallen_pose_cell(gu_idle_se, gu_th, cw, ch, foot_y, 78.0)

    # ==================== HERO 2: PEI ZHAO (`target_h = 166`) ====================
    pei_th = 166
    pei_is, pei_is_y = scale_pose_to_height(pei_idle_se, pei_th)
    pei_in, pei_in_y = scale_pose_to_height(pei_idle_ne, pei_th)
    pei_rs, pei_rs_y = scale_pose_to_height(pei_run_se, 162)
    pei_rn, pei_rn_y = scale_pose_to_height(pei_run_ne, 164)
    pei_sl, pei_sl_y = scale_pose_to_height(pei_slash, 154, max_w=246)

    pei_sheet = np.zeros((ch * rows_cnt, cw * cols, 4), dtype=np.uint8)
    for f in range(4):
        pei_sheet[0:ch, f * cw : (f + 1) * cw] = r6_act.render_canonical_idle_cell(pei_is, pei_is_y, cw, ch, foot_y, f, 4)
        pei_sheet[ch : 2 * ch, f * cw : (f + 1) * cw] = r6_act.render_canonical_idle_cell(pei_in, pei_in_y, cw, ch, foot_y, f, 4)

    pei_run_se_specs = [
        (pei_rs, pei_rs_y, 2.5, 2.0, -5.0, -10.0, 1.04, 0.98),
        (pei_rs, pei_rs_y, 1.0, -3.5, 8.0, 38.0, 0.86, 1.02),
        (pei_rs, pei_rs_y, 1.5, -1.0, 3.0, 14.0, 0.94, 1.00),
        (pei_rs, pei_rs_y, 3.0, 3.5, -7.0, -12.0, 1.05, 0.98),
        (pei_rs, pei_rs_y, 1.0, -3.5, 7.0, 38.0, 0.86, 1.02),
        (pei_rs, pei_rs_y, 1.5, 0.0, 1.5, 10.0, 0.96, 1.00),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p, tk_p, sx_p, sy_sc) in enumerate(pei_run_se_specs):
        pei_sheet[2 * ch : 3 * ch, f * cw : (f + 1) * cw] = place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p, lower_tuck_px=tk_p, scale_x=sx_p, scale_y=sy_sc
        )

    pei_run_ne_specs = [
        (pei_rn, pei_rn_y, 1.5, 1.5, -5.0, -8.0, 1.03, 0.99),
        (pei_rn, pei_rn_y, 0.0, -1.0, 4.0, 28.0, 0.90, 1.01),
        (pei_rn, pei_rn_y, -1.0, -1.5, 3.0, 6.0, 0.98, 1.00),
        (pei_rn, pei_rn_y, -2.0, -2.5, 6.0, -8.0, 1.03, 0.99),
        (pei_rn, pei_rn_y, 0.0, 1.0, -4.0, 28.0, 0.90, 1.01),
        (pei_rn, pei_rn_y, 1.0, 0.5, -2.0, 6.0, 0.98, 1.00),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p, tk_p, sx_p, sy_sc) in enumerate(pei_run_ne_specs):
        pei_sheet[3 * ch : 4 * ch, f * cw : (f + 1) * cw] = place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p, lower_tuck_px=tk_p, scale_x=sx_p, scale_y=sy_sc
        )

    pei_atk1_specs = [
        (pei_rs, pei_rs_y, -6.0, -4.5, 3.0, 0.98, 1.00),
        (pei_sl, pei_sl_y, 8.0, -2.0, -3.0, 0.96, 1.00),
        (pei_sl, pei_sl_y, 14.0, 2.5, -5.0, 1.05, 0.98),
        (pei_sl, pei_sl_y, 9.0, 4.5, -2.5, 0.98, 0.99),
        (pei_rs, pei_rs_y, 2.0, 1.5, 0.0, 0.94, 1.00),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p, sx_p, sy_sc) in enumerate(pei_atk1_specs):
        pei_sheet[4 * ch : 5 * ch, f * cw : (f + 1) * cw] = place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p, scale_x=sx_p, scale_y=sy_sc
        )

    pei_atk2_specs = [
        (pei_is, pei_is_y, -4.0, -3.5, 2.0, 0.98, 1.00),
        (pei_rs, pei_rs_y, -5.0, -3.0, 3.0, 1.00, 1.00),
        (pei_sl, pei_sl_y, 13.0, 5.5, -5.0, 1.04, 0.98),
        (pei_sl, pei_sl_y, 8.0, 6.5, -3.0, 0.97, 0.99),
        (pei_rs, pei_rs_y, 2.0, 1.0, 0.0, 0.94, 1.00),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p, sx_p, sy_sc) in enumerate(pei_atk2_specs):
        pei_sheet[5 * ch : 6 * ch, f * cw : (f + 1) * cw] = place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p, scale_x=sx_p, scale_y=sy_sc
        )

    pei_cast_specs = [
        (pei_sl, pei_sl_y, 0.0, -5.0, -2.0, 0.94, 1.01),
        (pei_sl, pei_sl_y, 0.0, -6.0, 2.5, 0.96, 1.00),
        (pei_sl, pei_sl_y, 0.0, -4.5, -3.0, 0.95, 1.01),
        (pei_sl, pei_sl_y, 12.0, 2.0, -4.5, 1.03, 0.98),
        (pei_sl, pei_sl_y, 7.0, 3.5, -2.0, 0.98, 0.99),
        (pei_rs, pei_rs_y, 2.0, 1.0, 0.0, 0.94, 1.00),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p, sx_p, sy_sc) in enumerate(pei_cast_specs):
        pei_sheet[6 * ch : 7 * ch, f * cw : (f + 1) * cw] = place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p, scale_x=sx_p, scale_y=sy_sc
        )

    pei_sheet[7 * ch : 8 * ch, 0:cw] = place_pose_on_cell(
        pei_rs, pei_rs_y, cw, ch, foot_y, dx_px=-8.0, rot_deg=-6.5, hem_sway_px=4.0, tint_rgb=(1.14, 0.92, 0.90)
    )
    pei_sheet[7 * ch : 8 * ch, cw : 2 * cw] = place_pose_on_cell(
        pei_rs, pei_rs_y, cw, ch, foot_y, dx_px=-4.0, rot_deg=-3.5, hem_sway_px=2.0, tint_rgb=(1.05, 0.96, 0.95)
    )
    pei_sheet[7 * ch : 8 * ch, 2 * cw : 3 * cw] = make_fallen_pose_cell(pei_idle_se, pei_th, cw, ch, foot_y, 70.0)
    pei_sheet[7 * ch : 8 * ch, 3 * cw : 4 * cw] = make_fallen_pose_cell(pei_idle_se, pei_th, cw, ch, foot_y, 78.0)

    # ==================== HERO 3: SHEN QINGHE (`target_h = 152`) ====================
    shen_th = 152
    sh_is, sh_is_y = scale_pose_to_height(shen_idle_se, shen_th)
    sh_in, sh_in_y = scale_pose_to_height(shen_idle_ne, shen_th)
    sh_rs, sh_rs_y = scale_pose_to_height(shen_run_se, 150)
    sh_rn, sh_rn_y = scale_pose_to_height(shen_run_ne, 152)
    sh_cs, sh_cs_y = scale_pose_to_height(shen_cast, 152, max_w=236)

    shen_sheet = np.zeros((ch * rows_cnt, cw * cols, 4), dtype=np.uint8)
    for f in range(4):
        shen_sheet[0:ch, f * cw : (f + 1) * cw] = r6_act.render_canonical_idle_cell(sh_is, sh_is_y, cw, ch, foot_y, f, 4)
        shen_sheet[ch : 2 * ch, f * cw : (f + 1) * cw] = r6_act.render_canonical_idle_cell(sh_in, sh_in_y, cw, ch, foot_y, f, 4)

    shen_run_se_specs = [
        (sh_rs, sh_rs_y, 2.5, 2.0, -5.0, -10.0, 1.05, 0.98),
        (sh_rs, sh_rs_y, 1.0, -3.5, 9.0, 42.0, 0.84, 1.02),
        (sh_rs, sh_rs_y, 1.5, -1.0, 3.0, 15.0, 0.94, 1.00),
        (sh_rs, sh_rs_y, 3.0, 3.5, -7.0, -12.0, 1.06, 0.98),
        (sh_rs, sh_rs_y, 1.0, -3.5, 8.0, 42.0, 0.84, 1.02),
        (sh_rs, sh_rs_y, 1.5, 0.0, 1.5, 10.0, 0.96, 1.00),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p, tk_p, sx_p, sy_sc) in enumerate(shen_run_se_specs):
        shen_sheet[2 * ch : 3 * ch, f * cw : (f + 1) * cw] = place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p, lower_tuck_px=tk_p, scale_x=sx_p, scale_y=sy_sc
        )

    shen_run_ne_specs = [
        (sh_rn, sh_rn_y, 1.5, 1.5, -5.0, -8.0, 1.03, 0.99),
        (sh_rn, sh_rn_y, 0.0, -1.0, 4.0, 28.0, 0.90, 1.01),
        (sh_rn, sh_rn_y, -1.0, -1.5, 3.0, 6.0, 0.98, 1.00),
        (sh_rn, sh_rn_y, -2.0, -2.5, 6.0, -8.0, 1.03, 0.99),
        (sh_rn, sh_rn_y, 0.0, 1.0, -4.0, 28.0, 0.90, 1.01),
        (sh_rn, sh_rn_y, 1.0, 0.5, -2.0, 6.0, 0.98, 1.00),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p, tk_p, sx_p, sy_sc) in enumerate(shen_run_ne_specs):
        shen_sheet[3 * ch : 4 * ch, f * cw : (f + 1) * cw] = place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p, lower_tuck_px=tk_p, scale_x=sx_p, scale_y=sy_sc
        )

    shen_atk1_specs = [
        (sh_rs, sh_rs_y, -4.0, -3.0, 2.5, 0.96, 1.00),
        (sh_cs, sh_cs_y, 6.0, -1.0, -2.5, 0.97, 1.00),
        (sh_cs, sh_cs_y, 10.0, 2.0, -4.5, 1.04, 0.99),
        (sh_cs, sh_cs_y, 6.0, 3.0, -2.0, 0.98, 1.00),
        (sh_rs, sh_rs_y, 1.0, 1.0, 0.0, 0.94, 1.00),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p, sx_p, sy_sc) in enumerate(shen_atk1_specs):
        shen_sheet[4 * ch : 5 * ch, f * cw : (f + 1) * cw] = place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p, scale_x=sx_p, scale_y=sy_sc
        )

    shen_atk2_specs = [
        (sh_is, sh_is_y, -3.0, -2.5, 2.0, 0.98, 1.00),
        (sh_rs, sh_rs_y, -4.0, -2.0, 2.5, 0.98, 1.00),
        (sh_cs, sh_cs_y, 11.0, 3.5, -5.0, 1.05, 0.98),
        (sh_cs, sh_cs_y, 7.0, 4.0, -2.5, 0.98, 0.99),
        (sh_rs, sh_rs_y, 1.0, 1.0, 0.0, 0.94, 1.00),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p, sx_p, sy_sc) in enumerate(shen_atk2_specs):
        shen_sheet[5 * ch : 6 * ch, f * cw : (f + 1) * cw] = place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p, scale_x=sx_p, scale_y=sy_sc
        )

    shen_cast_specs = [
        (sh_cs, sh_cs_y, 0.0, -2.0, -2.5, 0.98, 1.00),
        (sh_cs, sh_cs_y, 0.0, -3.0, 3.0, 1.01, 0.99),
        (sh_cs, sh_cs_y, 0.0, -1.5, -3.5, 1.00, 1.00),
        (sh_cs, sh_cs_y, 9.0, 1.5, -4.5, 1.04, 0.99),
        (sh_cs, sh_cs_y, 5.0, 2.5, -2.0, 0.98, 1.00),
        (sh_rs, sh_rs_y, 1.0, 0.5, 0.0, 0.95, 1.00),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p, sx_p, sy_sc) in enumerate(shen_cast_specs):
        shen_sheet[6 * ch : 7 * ch, f * cw : (f + 1) * cw] = place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p, scale_x=sx_p, scale_y=sy_sc
        )

    shen_sheet[7 * ch : 8 * ch, 0:cw] = place_pose_on_cell(
        sh_rs, sh_rs_y, cw, ch, foot_y, dx_px=-7.0, rot_deg=-5.5, hem_sway_px=4.0, tint_rgb=(1.14, 0.92, 0.90)
    )
    shen_sheet[7 * ch : 8 * ch, cw : 2 * cw] = place_pose_on_cell(
        sh_rs, sh_rs_y, cw, ch, foot_y, dx_px=-3.5, rot_deg=-3.0, hem_sway_px=2.0, tint_rgb=(1.05, 0.96, 0.95)
    )
    shen_sheet[7 * ch : 8 * ch, 2 * cw : 3 * cw] = make_fallen_pose_cell(shen_idle_se, shen_th, cw, ch, foot_y, 70.0)
    shen_sheet[7 * ch : 8 * ch, 3 * cw : 4 * cw] = make_fallen_pose_cell(shen_idle_se, shen_th, cw, ch, foot_y, 78.0)

    # Save & strictly assert all T1-F06-01 / T1-F06-05 / T2-F06-02 / T2-F06-04 / T4-W2-03 gates!
    hero_bundles = [
        ("gu_changqing", gu_sheet, "assets_src/sprites/r7_gu_multipose_raw.jpg"),
        ("pei_zhao", pei_sheet, "assets_src/sprites/r7_pei_shen_multipose_raw.jpg"),
        ("shen_qinghe", shen_sheet, "assets_src/sprites/r7_pei_shen_multipose_raw.jpg"),
    ]
    for aid, sheet_arr, src_rel in hero_bundles:
        sheet_clean = r6_act.clamp_song_ming_mineral_hsv(sheet_arr)
        assert count_fluorescent_pixels(sheet_clean) == 0, f"Fluorescent pixels in {aid}_sheet.png"

        rel_png = f"project/assets/sprites/{aid}_sheet.png"
        png_p = REPO_ROOT / rel_png
        json_p = REPO_ROOT / f"project/assets/sprites/{aid}_sheet.json"
        r2_act.save_rgba_clean(sheet_clean, str(png_p))

        # Update state_anchors cleanly for new forward-thrust / palm-cast silhouettes
        jdoc = json.loads(json_p.read_text(encoding="utf-8"))
        if "state_anchors" in jdoc:
            if aid != "shen_qinghe":
                jdoc["state_anchors"]["run_se"] = {"weapon": [34, -56], "cast": [22, -96]}
                jdoc["state_anchors"]["run_ne"] = {"weapon": [28, -56], "cast": [18, -96]}
                jdoc["state_anchors"]["attack_1"] = {"weapon": [96, -86], "cast": [28, -98]}
                jdoc["state_anchors"]["attack_2"] = {"weapon": [92, -78], "cast": [28, -98]}
            else:
                jdoc["state_anchors"]["attack_1"] = {"weapon": [68, -96], "cast": [68, -96]}
                jdoc["state_anchors"]["attack_2"] = {"weapon": [68, -92], "cast": [68, -92]}
        json_p.write_text(json.dumps(jdoc, indent=2) + "\n", encoding="utf-8")

        rep = analyze_sprite_sheet_cells(png_p, json_p, alpha_thresh=16)
        r_idle = rep["rows"]["idle_se"]
        r_run = rep["rows"]["run_se"]
        r_atk1 = rep["rows"]["attack_1"]
        r_atk2 = rep["rows"]["attack_2"]
        r_down = rep["rows"]["down"]

        idle_w, idle_h = int(r_idle["max_w"]), int(r_idle["max_h"])
        atk_w = max(int(r_atk1["max_w"]), int(r_atk2["max_w"]))
        down_h = int(r_down["max_h"])
        ext_ratio = atk_w / float(max(1, idle_w))
        down_ratio = down_h / float(max(1, idle_h))
        run_iou = float(r_run["intra_row_min_iou"])
        idle_atk_iou = float(rep["pairwise_row_iou"]["idle_se:attack_1"])
        idle_cast_iou = float(rep["pairwise_row_iou"]["idle_se:cast_loop"])
        tot_border = int(rep["total_border_opaque_px"])

        print(
            f"  [hero {aid}] idle={idle_w}x{idle_h}, atk_ext={ext_ratio:.2f}x, down={down_ratio:.2f}x, "
            f"run_iou={run_iou:.3f}, idle_atk_iou={idle_atk_iou:.3f}, idle_cast_iou={idle_cast_iou:.3f}, border={tot_border}"
        )
        assert 132 <= idle_h <= 178, f"{aid} idle_h={idle_h}"
        assert ext_ratio >= 1.32, f"{aid} ext_ratio={ext_ratio:.3f} < 1.32"
        assert down_ratio <= 0.75, f"{aid} down_ratio={down_ratio:.3f} > 0.75"
        assert run_iou <= 0.66, f"{aid} run_iou={run_iou:.3f} > 0.66"
        assert idle_atk_iou <= 0.50, f"{aid} idle_atk_iou={idle_atk_iou:.3f} > 0.50"
        assert idle_cast_iou <= 0.70, f"{aid} idle_cast_iou={idle_cast_iou:.3f} > 0.70"
        assert tot_border == 0, f"{aid} border opaque px={tot_border}"

        updates.append(
            {
                "path": rel_png,
                "source_path": src_rel,
                "category": "sprite_sheet",
                "creation_method": (
                    f"Gemini Imagen (2026-11-28, Song-Ming Gongbi multi-pose action & stride master sheets {src_rel}, "
                    f"r7_gu_thrust_backrun_raw.jpg, char_ref_party_pets_raw.jpg & char_ref_party_back_raw.jpg) + "
                    f"tools/build_polish_r7_combat_and_cave.py 8-row full hand-painted keyframe assembly ({aid})"
                ),
                "license": LIC_R7,
            }
        )
    return updates


def patch_subtle_npc_pet_enemy_motion() -> list[dict[str, str]]:
    """
    Re-renders the 9 NPC/pet/enemy sprite sheets with 42% gentler `run` / `attack` motion amplitudes
    so cave enemies and spirit pets move crisply without rubbery shear.
    """
    orig_fn = r6_act.render_grounded_shadowfree_frame

    def gentle_frame(
        fig_rgba: Image.Image,
        shoe_y: int,
        cell_w: int,
        cell_h: int,
        foot_y: int,
        state: str,
        frame_idx: int,
        total_frames: int,
        accent_rgb: tuple[int, int, int],
        is_quadruped: bool = False,
        is_enemy: bool = False,
    ) -> Image.Image:
        if state in ("idle", "hit_down"):
            return orig_fn(
                fig_rgba, shoe_y, cell_w, cell_h, foot_y, state, frame_idx, total_frames, accent_rgb, is_quadruped, is_enemy
            )
        src0 = np.asarray(fig_rgba, dtype=np.float32)
        sh0, sw0, _ = src0.shape
        pad = 28
        src = np.pad(src0, ((pad, pad), (pad, pad), (0, 0)), mode="constant", constant_values=0.0)
        sh, sw, _ = src.shape
        yy, xx = np.meshgrid(np.arange(sh, dtype=np.float32), np.arange(sw, dtype=np.float32), indexing="ij")
        yn = np.clip((yy - pad) / max(1.0, float(sh0 - 1)), -0.35, 1.35)
        xn = np.clip((xx - pad) / max(1.0, float(sw0 - 1)), -0.35, 1.35) - 0.5
        phase = (2.0 * math.pi * frame_idx) / max(1, total_frames)
        dx = np.zeros_like(xx)
        dy = np.zeros_like(yy)
        upper_w = np.clip((0.48 - yn) / 0.34, 0.0, 1.0)
        lower_w = np.clip((yn - 0.56) / 0.42, 0.0, 1.0)
        left_side = np.clip((-xn + 0.03) * 5.0, 0.0, 1.0)
        right_side = np.clip((xn + 0.03) * 5.0, 0.0, 1.0)
        sleeve_w = np.clip((yn - 0.25) / 0.30, 0.0, 1.0) * np.clip((0.72 - yn) / 0.18, 0.0, 1.0)
        lunge_px = 0.0

        if state == "run":
            stride = math.sin(phase)
            leg_amp = 5.8 if not is_quadruped else 7.2
            lift_amp = 4.2 if not is_quadruped else 3.8
            dx += lower_w * (left_side * stride * leg_amp - right_side * stride * leg_amp)
            dy -= lower_w * (left_side * max(0.0, -stride) * lift_amp + right_side * max(0.0, stride) * lift_amp)
            dx += upper_w * (2.0 + 1.2 * math.cos(phase))
            dy += upper_w * (0.8 * abs(math.sin(phase)))
        elif state == "attack_1":
            curves = [-4.0, 8.0, 10.5, 5.5, 1.5]
            rot_deg = [-3.0, 4.5, 5.8, 2.5, 0.0]
            lunge_px = curves[min(frame_idx, 4)]
            ang = math.radians(rot_deg[min(frame_idx, 4)])
            cx0, cy0 = pad + sw0 * 0.5, pad + sh0 * 0.75
            rx = (xx - cx0) * math.cos(ang) - (yy - cy0) * math.sin(ang) + cx0 - xx
            ry = (xx - cx0) * math.sin(ang) + (yy - cy0) * math.cos(ang) + cy0 - yy
            dx += upper_w * (rx + lunge_px * 0.35)
            dy += upper_w * ry
        elif state == "attack_2":
            curves = [-3.5, -1.0, 9.5, 7.5, 1.5]
            lunge_px = curves[min(frame_idx, 4)]
            dy -= upper_w * (3.0 if frame_idx in (1, 2) else 0.0)
            dx += upper_w * (lunge_px * 0.35)
        elif state == "cast":
            if frame_idx < 3:
                pulse = math.sin(frame_idx * 1.6)
                dy -= upper_w * (1.6 + 0.9 * pulse)
                dx += sleeve_w * (1.6 * math.cos(frame_idx * 2.0))
            else:
                lunge_px = 5.5 if frame_idx == 3 else (3.5 if frame_idx == 4 else 1.0)
                dx += upper_w * 2.5

        warped = cv2.remap(
            src,
            (xx - dx).astype(np.float32),
            (yy - dy).astype(np.float32),
            interpolation=cv2.INTER_LINEAR,
            borderMode=cv2.BORDER_CONSTANT,
            borderValue=(0, 0, 0, 0),
        )
        w_u8 = r6_act.clamp_song_ming_mineral_hsv(np.clip(warped, 0, 255).astype(np.uint8))
        w_u8[w_u8[..., 3] < 10] = 0
        canvas_arr = np.zeros((cell_h, cell_w, 4), dtype=np.uint8)
        paste_x = int(round((cell_w - sw0) * 0.5 - pad + lunge_px))
        paste_y = int(round(foot_y - (shoe_y + pad)))
        x0_d, y0_d = max(2, paste_x), max(2, paste_y)
        x1_d, y1_d = min(cell_w - 2, paste_x + sw), min(cell_h - 2, paste_y + sh)
        if x1_d > x0_d and y1_d > y0_d:
            r2_act.alpha_over_np(
                canvas_arr[y0_d:y1_d, x0_d:x1_d],
                w_u8[y0_d - paste_y : y0_d - paste_y + (y1_d - y0_d), x0_d - paste_x : x0_d - paste_x + (x1_d - x0_d)],
            )
        canvas_arr[foot_y + 4 :, :, :] = 0
        return Image.fromarray(r2_act.clean_zero_alpha(canvas_arr), mode="RGBA")

    r6_act.render_grounded_shadowfree_frame = gentle_frame
    try:
        return r6_act.build_all_grounded_npcs_pets_enemies()
    finally:
        r6_act.render_grounded_shadowfree_frame = orig_fn


def make_seamless_cosine_tile(raw_rgb: np.ndarray, out_size: int = 1024, overlap: int = 128) -> np.ndarray:
    """128px cosine-crossfade torus-seamless tile builder (zero grid seams!)."""
    im = Image.fromarray(raw_rgb, mode="RGB").resize((out_size + overlap, out_size + overlap), Image.Resampling.LANCZOS)
    arr = np.asarray(im, dtype=np.float32)
    w_1d = 0.5 - 0.5 * np.cos(np.linspace(0.0, math.pi, overlap, dtype=np.float32))

    # Horizontal seamless wrap
    h_blend = np.zeros((out_size + overlap, out_size, 3), dtype=np.float32)
    h_blend[:, :overlap, :] = (
        arr[:, :overlap, :] * w_1d[None, :, None] + arr[:, out_size : out_size + overlap, :] * (1.0 - w_1d[None, :, None])
    )
    h_blend[:, overlap:, :] = arr[:, overlap:out_size, :]

    # Vertical seamless wrap
    out = np.zeros((out_size, out_size, 3), dtype=np.float32)
    out[:overlap, :, :] = (
        h_blend[:overlap, :, :] * w_1d[:, None, None] + h_blend[out_size : out_size + overlap, :, :] * (1.0 - w_1d[:, None, None])
    )
    out[overlap:, :, :] = h_blend[overlap:out_size, :, :]

    rgba = np.zeros((out_size, out_size, 4), dtype=np.uint8)
    rgba[..., :3] = np.clip(out, 0, 255).astype(np.uint8)
    rgba[..., 3] = 255
    return r6_act.clamp_song_ming_mineral_hsv(rgba)


def build_r7_cave_and_pass_assets() -> list[dict[str, str]]:
    updates: list[dict[str, str]] = []

    # 1. `tex_cave_flagstone.png`: Natural irregular dark cavern limestone & moss floor (replaces 90-deg checkerboard!)
    slate_src = "assets_src/world/r7_cave_flat_slate_raw.jpg"
    raw_slate = np.asarray(Image.open(REPO_ROOT / slate_src).convert("RGB"))
    # Tone to deep damp cavern charcoal-slate (`#262F2D`..`#384440`) so characters & Jade Steles pop cleanly!
    dark_slate = np.clip(raw_slate.astype(np.float32) * np.array([0.74, 0.77, 0.75], dtype=np.float32), 0, 255).astype(np.uint8)
    flag_cell = make_seamless_cosine_tile(dark_slate, out_size=512, overlap=80)
    flag_2x2 = np.tile(flag_cell, (2, 2, 1)).astype(np.float32)
    yy_t, xx_t = np.meshgrid(np.arange(1024, dtype=np.float32), np.arange(1024, dtype=np.float32), indexing="ij")
    mod_f = 1.0 + 0.045 * np.sin(2.0 * math.pi * xx_t / 1024.0) * np.cos(2.0 * math.pi * yy_t / 1024.0)
    flag_2x2[..., :3] = np.clip(flag_2x2[..., :3] * mod_f[..., None], 0, 255)
    flag_tile = r6_act.clamp_song_ming_mineral_hsv(flag_2x2.astype(np.uint8))
    assert count_fluorescent_pixels(flag_tile) == 0
    flag_rel = "project/assets/world/tex_cave_flagstone.png"
    Image.fromarray(flag_tile[..., :3], mode="RGB").save(REPO_ROOT / flag_rel, format="PNG", optimize=False)
    updates.append(
        {
            "path": flag_rel,
            "source_path": slate_src,
            "category": "world_tile",
            "creation_method": (
                "Gemini Imagen (2026-11-28, prompt: 'Seamless uniform flat ground texture in Song-Ming Gongbi style: "
                "natural irregular polygonal dark cavern limestone and mossy slate flagstones, no 90-degree square grid') + "
                "tools/build_polish_r7_combat_and_cave.py 2x2 human-scale cosine-wrapped seamless tile"
            ),
            "license": LIC_R7,
        }
    )

    # 2. `tex_cave_pathway.png`: Slightly lighter worn pale-celadon/warm-limestone ancient cavern walkway tile
    #    (shares organic polygonal stone grammar with `tex_cave_flagstone.png` — ZERO 90-deg vs 35-deg grid clash!)
    lit_slate = np.clip(
        raw_slate.astype(np.float32) * np.array([1.05, 1.09, 1.04], dtype=np.float32) + np.array([12.0, 15.0, 11.0], dtype=np.float32),
        0,
        255,
    ).astype(np.uint8)
    lit_slate = np.rot90(lit_slate, 2)
    path_cell = make_seamless_cosine_tile(lit_slate, out_size=512, overlap=80)
    path_2x2 = np.tile(path_cell, (2, 2, 1)).astype(np.float32)
    mod_p = 1.0 + 0.045 * np.cos(2.0 * math.pi * xx_t / 1024.0) * np.sin(2.0 * math.pi * yy_t / 1024.0)
    path_2x2[..., :3] = np.clip(path_2x2[..., :3] * mod_p[..., None], 0, 255)
    path_tile = r6_act.clamp_song_ming_mineral_hsv(path_2x2.astype(np.uint8))
    assert count_fluorescent_pixels(path_tile) == 0
    path_rel = "project/assets/world/tex_cave_pathway.png"
    Image.fromarray(path_tile[..., :3], mode="RGB").save(REPO_ROOT / path_rel, format="PNG", optimize=False)
    updates.append(
        {
            "path": path_rel,
            "source_path": slate_src,
            "category": "world_tile",
            "creation_method": (
                "Gemini Imagen (2026-11-28, r7_cave_flat_slate_raw.jpg) + tools/build_polish_r7_combat_and_cave.py "
                "weathered pale-jade cavern walkway limestone grading & 128px cosine-wrapped seamless tile"
            ),
            "license": LIC_R7,
        }
    )

    # 3. `prop_cave_gnarled_roots.png` (from `r7_cave_grounded_roots_raw.jpg` — replaces vector octopus tripod!)
    roots_src = "assets_src/world/r7_cave_grounded_roots_raw.jpg"
    im_roots = np.asarray(Image.open(REPO_ROOT / roots_src).convert("RGB"))
    bg_roots = np.median(im_roots[:24, :24, :].astype(np.float32), axis=(0, 1))
    roots_cut = r5_town.extract_exterior_cutout(
        im_roots[48:970, 120:885], bg_roots, tol=22.0, extra_hole_boxes=[(20, 250, 740, 910)]
    )
    roots_rel = "project/assets/world/prop_cave_gnarled_roots.png"
    r5_town.save_grounded_rgba(roots_cut, 308, 324, roots_rel, shadow_alpha=82, pad_bot=4, lut_sat=0.92)
    updates.append(
        {
            "path": roots_rel,
            "source_path": roots_src,
            "category": "world_prop",
            "creation_method": (
                "Gemini Imagen (2026-11-28, prompt: '35-degree isometric Song-Ming Gongbi gnarled ancient underground "
                "spirit-tree stump and twisted roots gripping a mossy cavern boulder, cream background') + "
                "tools/build_polish_r7_combat_and_cave.py cutout & grounded shadow"
            ),
            "license": LIC_R7,
        }
    )

    # 4. `prop_cave_cliff_wall.png`, `prop_cave_stone_steps.png`, `prop_cave_stone_brazier.png` (from `r7_cave_arch_props_raw.jpg`)
    arch_src = "assets_src/world/r7_cave_arch_props_raw.jpg"
    im_arch = np.asarray(Image.open(REPO_ROOT / arch_src).convert("RGB"))
    bg_arch = np.median(im_arch[:20, 480:1360, :].astype(np.float32), axis=(0, 1))

    wall_cut = extract_clean_gongbi_pose(im_arch, (452, 92, 834, 566), bg_arch, tol=21.0)
    wall_rel = "project/assets/world/prop_cave_cliff_wall.png"
    r5_town.save_grounded_rgba(wall_cut, 268, 282, wall_rel, shadow_alpha=80, pad_bot=4, lut_sat=0.92)
    updates.append(
        {
            "path": wall_rel,
            "source_path": arch_src,
            "category": "world_prop",
            "creation_method": (
                "Gemini Imagen (2026-11-28, prompt: '35-degree isometric Song-Ming Gongbi rugged underground cavern "
                "axe-cut Fupicun slate cliff wall module with dark moss and stalactites') + "
                "tools/build_polish_r7_combat_and_cave.py cutout & grounded shadow"
            ),
            "license": LIC_R7,
        }
    )

    steps_cut = extract_clean_gongbi_pose(im_arch, (804, 236, 1146, 560), bg_arch, tol=21.0)
    steps_rel = "project/assets/world/prop_cave_stone_steps.png"
    r5_town.save_grounded_rgba(steps_cut, 236, 196, steps_rel, shadow_alpha=68, pad_bot=4, lut_sat=0.90)
    updates.append(
        {
            "path": steps_rel,
            "source_path": arch_src,
            "category": "world_prop",
            "creation_method": (
                "Gemini Imagen (2026-11-28, prompt: '35-degree isometric Song-Ming Gongbi weathered 4-step mossy "
                "cavern limestone staircase') + tools/build_polish_r7_combat_and_cave.py cutout & grounded shadow"
            ),
            "license": LIC_R7,
        }
    )

    brazier_cut = extract_clean_gongbi_pose(im_arch, (1180, 170, 1328, 570), bg_arch, tol=28.0)
    brazier_rel = "project/assets/world/prop_cave_stone_brazier.png"
    r5_town.save_grounded_rgba(brazier_cut, 104, 214, brazier_rel, shadow_alpha=82, pad_bot=4, lut_sat=0.95)
    updates.append(
        {
            "path": brazier_rel,
            "source_path": arch_src,
            "category": "world_prop",
            "creation_method": (
                "Gemini Imagen (2026-11-28, prompt: '35-degree isometric Song-Ming Gongbi ancient carved dark-stone "
                "cavern brazier pillar with warm amber charcoal flames') + tools/build_polish_r7_combat_and_cave.py cutout"
            ),
            "license": LIC_R7,
        }
    )

    # 5. `prop_cave_bagua_altar.png`, `prop_mountain_plank_bridge.png`, `prop_cave_stalagmite.png` (from `r7_cave_altar_bridge_raw.jpg`)
    ab_src = "assets_src/world/r7_cave_altar_bridge_raw.jpg"
    im_ab = np.asarray(Image.open(REPO_ROOT / ab_src).convert("RGB"))
    bg_ab = np.median(im_ab[:20, :, :].astype(np.float32), axis=(0, 1))

    altar_cut = extract_clean_gongbi_pose(im_ab, (28, 218, 452, 505), bg_ab, tol=20.5)
    altar_rel = "project/assets/world/prop_cave_bagua_altar.png"
    r5_town.save_grounded_rgba(altar_cut, 412, 256, altar_rel, shadow_alpha=64, pad_bot=4, lut_sat=0.92)
    updates.append(
        {
            "path": altar_rel,
            "source_path": ab_src,
            "category": "world_prop",
            "creation_method": (
                "Gemini Imagen (2026-11-28, prompt: '35-degree isometric Song-Ming Gongbi circular weathered stone "
                "ritual altar floor medallion with faded cinnabar Eight-Trigrams Bagua carvings') + "
                "tools/build_polish_r7_combat_and_cave.py cutout"
            ),
            "license": LIC_R7,
        }
    )

    bridge_cut = extract_clean_gongbi_pose(
        im_ab,
        (420, 124, 1004, 624),
        bg_ab,
        tol=21.0,
        pocket_boxes_norm=[(0.12, 0.14, 0.88, 0.62)],
        pocket_tol=18.0,
    )
    bridge_rel = "project/assets/world/prop_mountain_plank_bridge.png"
    r5_town.save_grounded_rgba(bridge_cut, 352, 268, bridge_rel, shadow_alpha=72, pad_bot=4, lut_sat=0.92)
    updates.append(
        {
            "path": bridge_rel,
            "source_path": ab_src,
            "category": "world_prop",
            "creation_method": (
                "Gemini Imagen (2026-11-28, prompt: '35-degree isometric Song-Ming Gongbi weathered cedar-wood "
                "mountain plank trestle bridge with mossy stone abutments and hemp rope railings') + "
                "tools/build_polish_r7_combat_and_cave.py cutout"
            ),
            "license": LIC_R7,
        }
    )

    stal_cut = extract_clean_gongbi_pose(im_ab, (964, 142, 1346, 600), bg_ab, tol=20.5)
    stal_rel = "project/assets/world/prop_cave_stalagmite.png"
    r5_town.save_grounded_rgba(stal_cut, 224, 246, stal_rel, shadow_alpha=80, pad_bot=4, lut_sat=0.92)
    updates.append(
        {
            "path": stal_rel,
            "source_path": ab_src,
            "category": "world_prop",
            "creation_method": (
                "Gemini Imagen (2026-11-28, prompt: '35-degree isometric Song-Ming Gongbi underground cavern "
                "stalagmite and mossy crag cluster with subtle celadon mineral veins') + "
                "tools/build_polish_r7_combat_and_cave.py cutout"
            ),
            "license": LIC_R7,
        }
    )

    # 6. `fg_cave_stalactite.png` (overhanging stalactite & root ceiling corner vignette from `r7_cave_corner_vines_raw.jpg`)
    cv_src = "assets_src/world/r7_cave_corner_vines_raw.jpg"
    im_cv = np.asarray(Image.open(REPO_ROOT / cv_src).convert("RGB"))
    bg_cv = np.median(im_cv[:20, :, :].astype(np.float32), axis=(0, 1))
    vig_cut = extract_clean_gongbi_pose(
        im_cv,
        (916, 118, 1324, 642),
        bg_cv,
        tol=21.5,
        pocket_boxes_norm=[(0.05, 0.08, 0.86, 0.65)],
        pocket_tol=18.5,
    )
    vig_sc = r6_act.crisp_resize_rgba(vig_cut, 256, 268, unsharp_pct=32)
    vig_arr = r6_act.clamp_song_ming_mineral_hsv(np.asarray(vig_sc, dtype=np.uint8))
    # Darken slightly into atmospheric foreground silhouette so it frames corners without distracting combat
    vig_arr[..., :3] = (vig_arr[..., :3].astype(np.float32) * 0.72).astype(np.uint8)
    assert count_fluorescent_pixels(vig_arr) == 0
    vig_rel = "project/assets/world/fg_cave_stalactite.png"
    r2_act.save_rgba_clean(vig_arr, str(REPO_ROOT / vig_rel))
    updates.append(
        {
            "path": vig_rel,
            "source_path": cv_src,
            "category": "world_foreground",
            "creation_method": (
                "Gemini Imagen (2026-11-28, prompt: 'Song-Ming Gongbi overhanging dark cavern stalactite and twisted "
                "root corner cluster') + tools/build_polish_r7_combat_and_cave.py silhouette vignette grading"
            ),
            "license": LIC_R7,
        }
    )

    return updates


def main() -> None:
    all_updates: list[dict[str, str]] = []
    all_updates.extend(build_r7_party_hero_sheets())
    all_updates.extend(patch_subtle_npc_pet_enemy_motion())
    all_updates.extend(build_r7_cave_and_pass_assets())

    manifest_path = REPO_ROOT / "docs/asset-manifest.json"
    doc = json.loads(manifest_path.read_text(encoding="utf-8"))
    by_path: dict[str, dict[str, Any]] = {str(e["path"]): e for e in doc.get("assets", [])}

    for item in all_updates:
        rel_p = item["path"]
        abs_p = REPO_ROOT / rel_p
        assert abs_p.is_file(), f"Missing built file: {rel_p}"
        by_path[rel_p] = {
            "path": rel_p,
            "source_path": item["source_path"],
            "category": item["category"],
            "creation_method": item["creation_method"],
            "license": item["license"],
            "sha256": sha256_file(abs_p),
        }

    doc["assets"] = [by_path[k] for k in sorted(by_path.keys())]
    manifest_path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"[build_polish_r7_combat_and_cave] Built & verified {len(all_updates)} R7 assets cleanly (manifest={len(doc['assets'])}).")


if __name__ == "__main__":
    main()
