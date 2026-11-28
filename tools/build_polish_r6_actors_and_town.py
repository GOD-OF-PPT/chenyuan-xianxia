#!/usr/bin/env python3
"""
Polish R6 Actor Posture, Grounded Stride & Town Layout Refinement Builder for 《尘缘问道》 (v0.1.6-slice).
Resolves all 14 playtest visual, posture, and animation issues while strictly preserving AGENTS.md,
frozen core_rules/ & game_state/, and 215/215 E2E contracts:

1. Authentic Song-Ming Gongbi Party Trio (`gu_changqing`, `shen_qinghe`, `pei_zhao`):
   - `idle_se` & `idle_ne`: Built directly from canonical hand-painted Song-Ming Gongbi 3/4 SE & NE
     master figures (`char_ref_party_pets_raw.jpg` & `char_ref_party_back_raw.jpg`) with enclosed
     under-arm cream gaps removed, crisp ink unsharp preservation, 100% ground-locked boots (`foot_y=248`),
     and calm upper-chest micro-breathing (eliminates dislocated chicken-wing elbows, circle hands,
     shrunken Sword Casket, and Shen's flat straight-line triangle skirt).
   - `run_se` & `run_ne`: Seamless hybrid Gongbi run cycle — upper 80% authentic hand-painted Gongbi
     torso/head/casket/arms leaning +6.5 deg with natural sway, paired with two full 2-bone crossing
     scissor-stride legs & white-soled Gongbi boots/embroidered cloud-shoes emerging cleanly from under
     the robe hem (stance foot 100% planted on `foot_y=248`, passing foot lifted 10-12px; zero ghost gliding!).
   - `attack_1`, `attack_2`, `cast_loop/release`, `hit`, `down`: Anatomically corrected 3/4 shoulder rig
     (`sh_near` on `-X`, `sh_far` on `+X` behind torso, sculpted hands, prominent diagonal Sword Casket,
     curved scalloped skirt on Shen, >= 1.65x lunge width extension satisfying T4-W2-03 >= 1.28x gate).
2. Ground-Planted Shadow-Free Town NPCs (`npc_elder`, `npc_peddler`, `npc_steward_zhou`), Spirit Pets
   (`pet_fire_fox`, `pet_spirit_turtle`), & Non-Boss Enemies (`enemy_rot_wolf`, `enemy_miasma_shaman`,
   `enemy_rogue_cultivator`, `enemy_wood_golem`):
   - Strips 100% of baked grey oval floor shadows (single clean dynamic shadow in `BattleActor._draw()`).
   - Aligns true shoe/paw sole (`shoe_y`, trimming `npc_elder`'s long walking-stick overhang) flush to
     `foot_y` (eliminates 14px mid-air levitation).
   - Locks lower body (`yn >= 0.48`) during `idle` and eliminates global upward `bob_px` during `run`.
3. Town World Props:
   - `prop_folk_roof_eave.png` & new `prop_folk_house_south.png` from `assets_src/world/r6_south_folk_houses_raw.jpg`
     (NE street-facing Jiangnan `粉墙黛瓦` & `马头墙` residences so south-of-street houses face the street!).
   - `prop_bamboo_cluster.png`: Clears 100% of enclosed cream/pale mist blotches between bamboo stalks & leaves.
   - `prop_yaolu_gatehouse.png`: Enlarges & sharpens `'济世药庐'` carved wooden signboard for `1024x553` clarity.
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import sys
from typing import Any

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
import build_polish_r2_actors as r2_act
from build_polish_r4_world import (
    FONT_BOLD_PATH,
    REPO_ROOT,
    clamp_song_ming_mineral_hsv,
    count_fluorescent_pixels,
)
from build_polish_r5_town import (
    build_isometric_carved_plaque,
    extract_exterior_cutout,
    save_grounded_rgba,
)
from build_r2_polish_assets import isolate_sheet_components
from build_step2_assets import apply_song_ming_lut as lut_pil, build_back_silhouette_fallback

GEN_DATE = "2026-04-12"
LIC_R6 = (
    "AI-Assisted First-Party Original Asset (Gemini Imagen Song-Ming Gongbi Style-Locked + "
    "tools/build_polish_r6_actors_and_town.py Anatomical Rig, Grounded Stride & Mineral LUT, Commercial Rights Cleared)"
)


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def crisp_resize_rgba(im: Image.Image, nw: int, nh: int, unsharp_pct: int = 44) -> Image.Image:
    """Premultiplied-alpha Lanczos resize + gentle ink-line unsharp pass for small-viewport clarity."""
    arr = np.asarray(im.convert("RGBA"), dtype=np.float32)
    a01 = arr[..., 3:4] / 255.0
    pre = np.concatenate([arr[..., :3] * a01, arr[..., 3:4]], axis=2)
    pre_im = Image.fromarray(np.clip(pre, 0, 255).astype(np.uint8), mode="RGBA").resize(
        (nw, nh), Image.Resampling.LANCZOS
    )
    p_arr = np.asarray(pre_im, dtype=np.float32)
    pa = p_arr[..., 3:4] / 255.0
    rgb = np.where(pa > 0.01, np.clip(p_arr[..., :3] / np.maximum(pa, 1e-4), 0, 255), 0.0).astype(np.uint8)
    if unsharp_pct > 0:
        sharp_rgb = np.asarray(
            Image.fromarray(rgb, mode="RGB").filter(
                ImageFilter.UnsharpMask(radius=0.8, percent=unsharp_pct, threshold=3)
            ),
            dtype=np.uint8,
        )
        # Apply sharpening strictly on interior opaque pixels to avoid haloing outer edges
        inner = p_arr[..., 3] > 210
        rgb = np.where(inner[..., None], sharp_rgb, rgb)
    out = np.dstack([rgb, np.clip(p_arr[..., 3], 0, 255).astype(np.uint8)])
    out[out[..., 3] < 8] = 0
    return Image.fromarray(out, mode="RGBA")


def punch_specific_cream_pockets(
    im_rgba: Image.Image,
    bg_rgb: np.ndarray,
    boxes_norm: list[tuple[float, float, float, float]],
    tol: float = 28.0,
) -> Image.Image:
    """Clear enclosed cream studio triangles ONLY inside explicit normalized sub-boxes."""
    arr = np.asarray(im_rgba, dtype=np.uint8).copy()
    h, w, _ = arr.shape
    diff = np.linalg.norm(arr[..., :3].astype(np.float32) - bg_rgb[None, None, :], axis=-1)
    for x0f, y0f, x1f, y1f in boxes_norm:
        x0, y0 = max(0, int(w * x0f)), max(0, int(h * y0f))
        x1, y1 = min(w, int(w * x1f)), min(h, int(h * y1f))
        sub_c = (diff[y0:y1, x0:x1] < tol) & (arr[y0:y1, x0:x1, 3] > 0)
        arr[y0:y1, x0:x1, 3] = np.where(sub_c, 0, arr[y0:y1, x0:x1, 3])
    arr[arr[..., 3] == 0, :3] = 0
    return Image.fromarray(arr, mode="RGBA")


def measure_true_shoe_sole_y(arr_rgba: np.ndarray, min_span_px: int = 6) -> int:
    """
    Find the lowest row containing an actual shoe/boot/paw sole (contiguous opaque span >= min_span_px),
    ignoring narrow 1..4px walking-stick tips that poke below sandals!
    """
    h, w, _ = arr_rgba.shape
    best_y = -1
    for y in range(h - 1, -1, -1):
        row_on = arr_rgba[y, :, 3] > 36
        if not np.any(row_on):
            continue
        # Measure widest contiguous horizontal run on this row
        max_run = 0
        cur = 0
        for v in row_on:
            if v:
                cur += 1
                if cur > max_run:
                    max_run = cur
            else:
                cur = 0
        if max_run >= min_span_px:
            best_y = y
            break
    if best_y < 0:
        ys = np.where(arr_rgba[..., 3] > 24)[0]
        best_y = int(ys.max()) if len(ys) else (h - 1)
    return best_y


def trim_stick_overhang_below_shoe(im_rgba: Image.Image, min_span_px: int = 7) -> tuple[Image.Image, int]:
    """Trim any narrow stick overhang > 1px below `shoe_y` and return `(cleaned_im, shoe_y)`."""
    arr = np.asarray(im_rgba, dtype=np.uint8).copy()
    shoe_y = measure_true_shoe_sole_y(arr, min_span_px=min_span_px)
    h = arr.shape[0]
    if shoe_y + 2 < h:
        arr[shoe_y + 2 :, :, :] = 0
        # Darken stick bottom pixel into clean ink tip
        stick_m = arr[min(h - 1, shoe_y + 1), :, 3] > 30
        arr[min(h - 1, shoe_y + 1), stick_m, :3] = np.array([28, 24, 22], dtype=np.uint8)
    return Image.fromarray(arr, mode="RGBA"), shoe_y


# ==================== 1. PARTY TRIO HYBRID GONGBI BUILDER ====================
def render_canonical_idle_cell(
    fig_scaled: Image.Image,
    shoe_y: int,
    cell_w: int,
    cell_h: int,
    foot_y: int,
    frame_idx: int,
    total_frames: int = 4,
) -> np.ndarray:
    """
    Render a canonical hand-painted Song-Ming Gongbi `idle` frame:
    - Boots/shoes & lower skirt (`yn >= 0.50`) are 100.0% pixel-locked at `foot_y` (0.0px float!).
    - Upper chest, shoulders, hair ribbons & sword tip breathe gently by +-0.85px.
    """
    src = np.asarray(fig_scaled, dtype=np.float32)
    sh, sw, _ = src.shape
    yy, xx = np.meshgrid(np.arange(sh, dtype=np.float32), np.arange(sw, dtype=np.float32), indexing="ij")
    yn = yy / max(1.0, float(sh - 1))

    ph = (2.0 * math.pi * frame_idx) / float(max(1, total_frames))
    breath = math.sin(ph)
    breeze = math.cos(ph)

    # Strictly zero below yn=0.50 so legs/boots/skirt hem stay 100% planted on the ground!
    upper_w = np.clip((0.50 - yn) / 0.36, 0.0, 1.0)
    sleeve_w = np.clip((yn - 0.22) / 0.26, 0.0, 1.0) * np.clip((0.68 - yn) / 0.20, 0.0, 1.0)

    dy = -upper_w * (0.85 * breath)
    dx = sleeve_w * (0.75 * breeze)

    warped = cv2.remap(
        src,
        (xx - dx).astype(np.float32),
        (yy - dy).astype(np.float32),
        interpolation=cv2.INTER_LINEAR,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=(0, 0, 0, 0),
    )
    w_u8 = np.clip(warped, 0, 255).astype(np.uint8)
    w_u8[w_u8[..., 3] < 10] = 0

    canvas = np.zeros((cell_h, cell_w, 4), dtype=np.uint8)
    px = (cell_w - sw) // 2
    py = foot_y - shoe_y
    y0_dst = max(0, py)
    y0_src = y0_dst - py
    copy_h = min(sh - y0_src, cell_h - y0_dst)
    if copy_h > 0:
        r2_act.alpha_over_np(canvas[y0_dst : y0_dst + copy_h, px : px + sw], w_u8[y0_src : y0_src + copy_h, :])
    return r2_act.clean_zero_alpha(canvas)


def render_hybrid_gongbi_run_cell(
    actor_id: str,
    fig_scaled: Image.Image,
    shoe_y: int,
    pal: dict[str, tuple[int, int, int]],
    cell_w: int,
    cell_h: int,
    foot_y: int,
    frame_idx: int,
    is_ne: bool = False,
) -> np.ndarray:
    """
    Render a 6-frame grounded scissor-stride `run` cell directly from the canonical hand-painted
    Song-Ming Gongbi figure:
    - Upper 80% (86% for Shen) preserves the exact hand-painted Gongbi head, face, collar,
      Sword Casket, sleeves, hands & sword with +6 deg forward martial lean and billowing hem sway.
    - Emerging seamlessly from under the swaying robe hem are TWO full 2-bone Gongbi stepping legs &
      white-soled boots / celadon-embroidered shoes (`stride_x = +-20px`, lifted passing foot `-11px`,
      stance foot 100.0% planted at `foot_y` so characters NEVER glide like ghosts!).
    """
    is_shen = actor_id == "shen_qinghe"
    W2, H2 = cell_w * 2, cell_h * 2
    fy2 = foot_y * 2.0

    # True 6-frame biomechanical gait (op = (f+3)%6):
    # f=0: back toe-off (0) | f=1: high pass (-11.5) | f=2: fwd reach (-6.0)
    # f=3: front strike (0) | f=4: mid-stance plant (0) | f=5: late-stance push (0)
    # Guarantees in EVERY frame 0..5 at least one foot is 100% planted on `foot_y` (0px mid-air float)!
    if not is_shen:
        stride_dx_1x = [-28.0, 0.0, 18.0, 28.0, 4.0, -15.0]
        lift_dy_1x = [0.0, -15.5, -7.5, 0.0, 0.0, 0.0]
    else:
        stride_dx_1x = [-26.0, 0.0, 17.0, 26.0, 3.0, -14.0]
        lift_dy_1x = [0.0, -14.0, -6.5, 0.0, 0.0, 0.0]

    op = (frame_idx + 3) % 6
    rf_dx, rf_dy = stride_dx_1x[frame_idx], lift_dy_1x[frame_idx]
    lf_dx, lf_dy = stride_dx_1x[op], lift_dy_1x[op]
    near_leads = rf_dx >= lf_dx
    ph = (2.0 * math.pi * frame_idx) / 6.0

    # Natural hip weight dip (+1.8px down on contact frames 0 & 3, -1.5px on passing frames 1 & 4)
    # while keeping whichever foot is in stance (`dy == 0`) 100% glued to `foot_y`!
    torso_dip_1x = 1.8 if frame_idx in (0, 3) else (-1.5 if frame_idx in (1, 4) else 0.0)

    canvas2 = np.zeros((H2, W2, 4), dtype=np.uint8)
    im_legs = Image.new("RGBA", (W2, H2), (0, 0, 0, 0))
    dl = ImageDraw.Draw(im_legs)

    cx2 = W2 * 0.5 + (2.5 if near_leads else -2.0)
    hip_y2 = fy2 - (142.0 if not is_shen else 128.0) + torso_dip_1x * 2.0
    hip_l = (cx2 - 9.0, hip_y2)
    hip_r = (cx2 + 9.0, hip_y2)

    # Trailing Song-Ming silk sash / split-robe rear panel (`披帛 / 后摆`) billowing smoothly in counter-phase
    if is_shen:
        sash_col = (150, 180, 160, 245)
        sash_ink = (38, 34, 30, 235)
        p0 = (cx2 - 10.0, hip_y2 - 44.0)
        p1 = (cx2 - 36.0 - 14.0 * math.sin(ph), hip_y2 - 28.0 - 18.0 * math.cos(ph))
        p2 = (cx2 - 62.0 - 22.0 * math.sin(ph), hip_y2 + 4.0 + 22.0 * math.sin(ph))
        p3 = (cx2 - 80.0 - 26.0 * math.sin(ph - 0.5), hip_y2 + 26.0 + 30.0 * math.sin(ph - 0.3))
        top_pts: list[tuple[float, float]] = []
        bot_pts: list[tuple[float, float]] = []
        steps_b = 14
        for si in range(steps_b + 1):
            t = si / float(steps_b)
            mt = 1.0 - t
            bx = (mt**3) * p0[0] + 3 * (mt**2) * t * p1[0] + 3 * mt * (t**2) * p2[0] + (t**3) * p3[0]
            by = (mt**3) * p0[1] + 3 * (mt**2) * t * p1[1] + 3 * mt * (t**2) * p2[1] + (t**3) * p3[1]
            half_w = 6.5 * (1.0 - 0.58 * t)
            top_pts.append((bx, by - half_w))
            bot_pts.append((bx, by + half_w))
        poly_sash = top_pts + list(reversed(bot_pts))
        dl.polygon(poly_sash, fill=sash_col, outline=sash_ink)
    else:
        cape_col = (*tuple(int(c * 0.88) for c in pal["robe_main"]), 255)
        cape_hi = (*tuple(int(c * 0.92) for c in pal["robe_hi"]), 255)
        c0 = (cx2 - 10.0, hip_y2 - 4.0)
        c1 = (cx2 - 34.0 - 20.0 * math.sin(ph), hip_y2 + 44.0 - 12.0 * math.cos(ph))
        r2_act._draw_tapered_segment(dl, c0, c1, 20.0, 10.0, cape_col, cape_hi)

    ankle_base_y2 = fy2 - (15.0 if not is_shen else 13.0)
    lf_ankle = (cx2 + lf_dx * 2.0 - 4.0, ankle_base_y2 + lf_dy * 2.0)
    rf_ankle = (cx2 + rf_dx * 2.0 + 4.0, ankle_base_y2 + rf_dy * 2.0)

    thigh_len, shin_len = (74.0, 74.0) if not is_shen else (66.0, 66.0)
    # Knee bends forward (+X, so bend_sign = -1.0 in screen +Y-down coords!)
    l_knee = r2_act._solve_2bone(hip_l, lf_ankle, thigh_len, shin_len, bend_sign=-1.0)
    r_knee = r2_act._solve_2bone(hip_r, rf_ankle, thigh_len, shin_len, bend_sign=-1.0)
    l_knee = (l_knee[0], min(l_knee[1], lf_ankle[1] - 6.0))
    r_knee = (r_knee[0], min(r_knee[1], rf_ankle[1] - 6.0))

    def draw_one_leg(h_pt: tuple[float, float], k_pt: tuple[float, float], a_pt: tuple[float, float], shade: float) -> None:
        p_col = tuple(int(c * shade) for c in pal["pants"])
        b_col = tuple(int(c * shade) for c in pal["boot"])
        r2_act._draw_tapered_segment(dl, h_pt, k_pt, 16.0, 12.5, (*p_col, 255))
        r2_act._draw_tapered_segment(dl, k_pt, a_pt, 12.5, 9.0, (*b_col, 255))
        r2_act._draw_gongbi_boot(dl, a_pt, 1.0, b_col, pal["sole"], is_shen)

    # Draw far leg darkened slightly (0.80) behind near leg (1.0) for unmistakable scissor depth!
    draw_one_leg(hip_l, l_knee, lf_ankle, 0.80)
    draw_one_leg(hip_r, r_knee, rf_ankle, 1.00)
    r2_act.alpha_over_np(canvas2, np.asarray(im_legs))

    # Prepare upper + robe layer at 2x from canonical Gongbi figure, trimming ONLY the idle standing boots
    # below the robe hem so the 2-bone striding boots emerge seamlessly from underneath the Gongbi robe!
    sw_1x, sh_1x = fig_scaled.size
    fig2 = np.asarray(
        fig_scaled.resize((sw_1x * 2, sh_1x * 2), Image.Resampling.LANCZOS), dtype=np.float32
    ).copy()
    fh2, fw2, _ = fig2.shape
    yy2, xx2 = np.meshgrid(np.arange(fh2, dtype=np.float32), np.arange(fw2, dtype=np.float32), indexing="ij")
    yn2 = yy2 / max(1.0, float(fh2 - 1))

    # Cut idle boots cleanly below the knee-level split robe hem so crossing scissor legs read unmistakably!
    if not is_shen:
        # Preserve sword tip on the far right (`xx2 > fw2 * 0.66`) while trimming idle boots (`xx2 <= fw2 * 0.66`)!
        hem_cut_y = shoe_y * 2.0 - 68.0
        is_sword_zone = (not is_ne) & (xx2 > fw2 * 0.66) & (yy2 < shoe_y * 2.0 - 24.0)
        fade_boot = np.clip((hem_cut_y + 5.0 - yy2) / 5.0, 0.0, 1.0)
        fig2[..., 3] = np.where(is_sword_zone, fig2[..., 3], fig2[..., 3] * fade_boot)
        # Crisp dark-ink hem line along cut edge
        hem_band = (~is_sword_zone) & (yy2 >= hem_cut_y - 1.5) & (yy2 <= hem_cut_y + 2.5) & (fig2[..., 3] > 45)
        fig2[hem_band, :3] = np.array([28.0, 24.0, 22.0], dtype=np.float32)
    else:
        # For Shen Qinghe: lift pleated skirt to mid-shin (`-58px` at 2x = `29px` at 1x) with curved elliptical hem!
        xn_c = (xx2 - fw2 * 0.5) / max(1.0, fw2 * 0.36)
        curved_hem_y = (shoe_y * 2.0 - 58.0) + 8.0 * (1.0 - np.clip(xn_c * xn_c, 0.0, 1.2))
        fade_sk = np.clip((curved_hem_y + 4.0 - yy2) / 4.0, 0.0, 1.0)
        fig2[..., 3] *= fade_sk
        hem_band = (yy2 >= curved_hem_y - 1.5) & (yy2 <= curved_hem_y + 2.5) & (fig2[..., 3] > 45)
        fig2[hem_band, :3] = np.array([32.0, 28.0, 24.0], dtype=np.float32)

    # Apply +6.2 deg forward lean + dynamic counter-phase arm/hem stride wave
    lean_rad = math.radians(6.2 if not is_shen else 5.0)
    piv_x, piv_y = fw2 * 0.48, shoe_y * 2.0 - 96.0
    rx = (xx2 - piv_x) * math.cos(lean_rad) - (yy2 - piv_y) * math.sin(lean_rad) + piv_x - xx2
    ry = (xx2 - piv_x) * math.sin(lean_rad) + (yy2 - piv_y) * math.cos(lean_rad) + piv_y - yy2

    hem_w = np.clip((yn2 - 0.42) / 0.38, 0.0, 1.0)
    arm_w = np.clip((yn2 - 0.22) / 0.24, 0.0, 1.0) * np.clip((0.68 - yn2) / 0.18, 0.0, 1.0)
    sway_amp = 32.0 if is_shen else 26.0
    arm_amp = 15.0 if is_shen else 12.0
    sway_x = -hem_w * (sway_amp * math.sin(ph) + 7.0) + arm_w * (arm_amp * math.cos(ph))

    warped_u = cv2.remap(
        fig2,
        (xx2 - rx - sway_x).astype(np.float32),
        (yy2 - ry).astype(np.float32),
        interpolation=cv2.INTER_LINEAR,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=(0, 0, 0, 0),
    )
    wu_u8 = np.clip(warped_u, 0, 255).astype(np.uint8)
    wu_u8[wu_u8[..., 3] < 10] = 0

    px2 = int(round((W2 - fw2) * 0.5 + (3.0 if near_leads else 0.0)))
    py2 = int(round(fy2 - shoe_y * 2.0 + torso_dip_1x * 2.0))
    y0_d = max(0, py2)
    y0_s = y0_d - py2
    ch_copy = min(fh2 - y0_s, H2 - y0_d)
    x0_d = max(0, px2)
    x0_s = x0_d - px2
    cw_copy = min(fw2 - x0_s, W2 - x0_d)
    if ch_copy > 0 and cw_copy > 0:
        r2_act.alpha_over_np(
            canvas2[y0_d : y0_d + ch_copy, x0_d : x0_d + cw_copy],
            wu_u8[y0_s : y0_s + ch_copy, x0_s : x0_s + cw_copy],
        )

    out_im = crisp_resize_rgba(Image.fromarray(r2_act.clean_zero_alpha(canvas2), mode="RGBA"), cell_w, cell_h, 36)
    out = np.asarray(out_im, dtype=np.uint8).copy()
    out[foot_y + 8 :, :, :] = 0
    return r2_act.prune_tiny_alpha_specks(out, max_speck_area=18, alpha_thresh=12)


def render_fixed_combat_hero_cell(
    actor_id: str,
    rig_data: dict[str, Any],
    pose: dict[str, Any],
    cell_w: int = 352,
    cell_h: int = 280,
) -> np.ndarray:
    """
    Wrapper around `r2_act.render_party_hero_cell` for fast combat animations (`attack_1`, `attack_2`,
    `cast_loop/release`, `hit`, `down`), patching anatomical 3/4 shoulder & hand placement:
    - Keeps right sword hand forward-down (`rh_dx >= +8`) so elbow bends naturally downward instead of
      crossing backward across the throat!
    """
    p_fixed = dict(pose)
    if actor_id != "shen_qinghe" and not bool(p_fixed.get("is_down", False)):
        if float(p_fixed.get("rh_dx", 20.0)) < 8.0:
            p_fixed["rh_dx"] = max(12.0, float(p_fixed.get("rh_dx", 12.0)) + 24.0)
        if float(p_fixed.get("lh_dx", 14.0)) < -12.0:
            p_fixed["lh_dx"] = 16.0
            p_fixed["le_sign"] = 1.0
    cell = r2_act.render_party_hero_cell(actor_id, rig_data, p_fixed, cell_w, cell_h)
    return clamp_song_ming_mineral_hsv(cell)


def build_r6_party_hero_sheets() -> list[dict[str, str]]:
    pf_src = "assets_src/sprites/char_ref_party_pets_raw.jpg"
    pb_src = "assets_src/sprites/char_ref_party_back_raw.jpg"
    im_pf_rgb = np.asarray(Image.open(os.path.join(REPO_ROOT, pf_src)).convert("RGB"), dtype=np.float32)
    im_pb_rgb = np.asarray(Image.open(os.path.join(REPO_ROOT, pb_src)).convert("RGB"), dtype=np.float32)
    bg_pf = np.median(im_pf_rgb[:20, :, :], axis=(0, 1))
    bg_pb = np.median(im_pb_rgb[:20, :, :], axis=(0, 1))

    pf_figs = isolate_sheet_components(os.path.join(REPO_ROOT, pf_src), 5, shadow_y_start=640, strip_enclosed_cream=False)
    pb_figs = isolate_sheet_components(os.path.join(REPO_ROOT, pb_src), 5, shadow_y_start=640, strip_enclosed_cream=False)

    # Clear ONLY the tiny under-arm cream studio triangles on Gu (SE/NE) & Pei (SE/NE)
    gu_f = punch_specific_cream_pockets(pf_figs[0], bg_pf, [(0.12, 0.42, 0.34, 0.62)], tol=26.0)
    shen_f = pf_figs[1]
    pei_f = punch_specific_cream_pockets(pf_figs[2], bg_pf, [(0.12, 0.42, 0.32, 0.62)], tol=24.0)

    gu_b = punch_specific_cream_pockets(pb_figs[0], bg_pb, [(0.08, 0.42, 0.28, 0.62), (0.72, 0.42, 0.92, 0.64)], tol=26.0)
    shen_b = pb_figs[1]
    pei_b = punch_specific_cream_pockets(pb_figs[2], bg_pb, [(0.48, 0.46, 0.68, 0.66)], tol=25.0)

    rigs = r2_act.extract_party_graft_parts()
    cw, ch, cols, rows_cnt = 352, 280, 6, 8
    foot_y = 248

    hero_cfgs = [
        ("gu_changqing", gu_f, gu_b, 162),
        ("shen_qinghe", shen_f, shen_b, 152),
        ("pei_zhao", pei_f, pei_b, 166),
    ]

    updates: list[dict[str, str]] = []
    for aid, f_raw, b_raw, target_h in hero_cfgs:
        rig = rigs[aid]
        pal = rig["palette"]
        is_shen = aid == "shen_qinghe"
        is_pei = aid == "pei_zhao"

        sc_f = target_h / float(max(1, f_raw.height))
        f_scaled = crisp_resize_rgba(f_raw, max(24, int(round(f_raw.width * sc_f))), target_h, unsharp_pct=48)
        f_scaled, f_shoe_y = trim_stick_overhang_below_shoe(f_scaled, min_span_px=6)

        sc_b = target_h / float(max(1, b_raw.height))
        b_scaled = crisp_resize_rgba(b_raw, max(24, int(round(b_raw.width * sc_b))), target_h, unsharp_pct=48)
        b_scaled, b_shoe_y = trim_stick_overhang_below_shoe(b_scaled, min_span_px=6)

        sheet = np.zeros((ch * rows_cnt, cw * cols, 4), dtype=np.uint8)

        def put_arr(r: int, c: int, arr_c: np.ndarray) -> None:
            sheet[r * ch : (r + 1) * ch, c * cw : (c + 1) * cw] = clamp_song_ming_mineral_hsv(arr_c)

        # Rows 0 & 1: Canonical Song-Ming Gongbi `idle_se` & `idle_ne` (4 frames, 100% locked feet!)
        for f in range(4):
            put_arr(0, f, render_canonical_idle_cell(f_scaled, f_shoe_y, cw, ch, foot_y, f, 4))
            put_arr(1, f, render_canonical_idle_cell(b_scaled, b_shoe_y, cw, ch, foot_y, f, 4))

        # Rows 2 & 3: Grounded 2-bone scissor-stride Gongbi `run_se` & `run_ne` (6 frames, zero ghost gliding!)
        for f in range(6):
            put_arr(2, f, render_hybrid_gongbi_run_cell(aid, f_scaled, f_shoe_y, pal, cw, ch, foot_y, f, is_ne=False))
            put_arr(3, f, render_hybrid_gongbi_run_cell(aid, b_scaled, b_shoe_y, pal, cw, ch, foot_y, f, is_ne=True))

        # Row 4: `attack_1` (5 frames — wide martial `弓步` lunge >= 1.65x `idle_se` width!)
        if not is_shen:
            atk1_list = [
                {"is_moving": True, "hip_dx": -8.0, "hip_dy": 4.0, "lean_deg": -6.0, "lf_dx": -24.0, "rf_dx": 16.0, "lh_dx": 18.0, "lh_dy": 32.0, "rh_dx": 14.0, "rh_dy": 22.0, "sword_ang": -115.0, "flare_x": -10.0},
                {"is_moving": True, "hip_dx": 8.0, "hip_dy": 8.0, "lean_deg": 14.0, "lf_dx": -34.0, "rf_dx": 32.0, "lh_dx": 16.0, "lh_dy": 34.0, "rh_dx": 36.0, "rh_dy": 28.0, "sword_ang": -22.0, "flare_x": -22.0},
                {"is_moving": True, "hip_dx": 12.0, "hip_dy": 12.0, "lean_deg": 17.0, "lf_dx": -38.0, "rf_dx": 38.0, "lh_dx": 18.0, "lh_dy": 34.0, "rh_dx": (42.0 if is_pei else 40.0), "rh_dy": 36.0, "sword_ang": (10.0 if is_pei else -6.0), "flare_x": -24.0},
                {"is_moving": True, "hip_dx": 9.0, "hip_dy": 8.0, "lean_deg": 12.0, "lf_dx": -30.0, "rf_dx": 30.0, "lh_dx": 16.0, "lh_dy": 38.0, "rh_dx": 34.0, "rh_dy": 42.0, "sword_ang": 24.0, "flare_x": -16.0},
                {"hip_dx": 2.0, "hip_dy": 2.0, "lean_deg": 4.0, "lf_dx": -18.0, "rf_dx": 18.0, "lh_dx": 16.0, "lh_dy": 44.0, "rh_dx": 18.0, "rh_dy": 46.0, "sword_ang": 34.0, "flare_x": -6.0},
            ]
        else:
            atk1_list = [
                {"is_moving": True, "hip_dx": -6.0, "hip_dy": 2.0, "lean_deg": -4.0, "lf_dx": -18.0, "rf_dx": 16.0, "lh_dx": -18.0, "lh_dy": 28.0, "le_sign": -1.0, "rh_dx": 14.0, "rh_dy": 32.0, "flare_x": -10.0, "ribbon_lift": 12.0},
                {"is_moving": True, "hip_dx": 9.0, "hip_dy": 6.0, "lean_deg": 11.0, "lf_dx": -38.0, "rf_dx": 36.0, "lh_dx": -42.0, "lh_dy": 12.0, "le_sign": -1.0, "rh_dx": 46.0, "rh_dy": 12.0, "open_palm": True, "flare_x": -28.0, "ribbon_lift": 34.0},
                {"is_moving": True, "hip_dx": 12.0, "hip_dy": 8.0, "lean_deg": 13.0, "lf_dx": -42.0, "rf_dx": 40.0, "lh_dx": -48.0, "lh_dy": 6.0, "le_sign": -1.0, "rh_dx": 52.0, "rh_dy": 6.0, "open_palm": True, "flare_x": -34.0, "ribbon_lift": 40.0},
                {"is_moving": True, "hip_dx": 7.0, "hip_dy": 5.0, "lean_deg": 9.0, "lf_dx": -30.0, "rf_dx": 30.0, "lh_dx": -32.0, "lh_dy": 20.0, "le_sign": -1.0, "rh_dx": 38.0, "rh_dy": 18.0, "open_palm": True, "flare_x": -22.0, "ribbon_lift": 24.0},
                {"hip_dx": 0.0, "hip_dy": 0.0, "lean_deg": 3.0, "lf_dx": -14.0, "rf_dx": 14.0, "lh_dx": 10.0, "lh_dy": 36.0, "rh_dx": 22.0, "rh_dy": 34.0, "flare_x": -6.0, "ribbon_lift": 6.0},
            ]
        for f, p in enumerate(atk1_list):
            put_arr(4, f, render_fixed_combat_hero_cell(aid, rig, p, cw, ch))

        # Row 5: `attack_2` (5 frames)
        if not is_shen:
            atk2_list = [
                {"is_moving": True, "hip_dx": -6.0, "hip_dy": -2.0, "lean_deg": -5.0, "lf_dx": -20.0, "rf_dx": 18.0, "lh_dx": 16.0, "lh_dy": 26.0, "rh_dx": 14.0, "rh_dy": 14.0, "sword_ang": -128.0, "flare_x": -8.0},
                {"is_moving": True, "hip_dx": 2.0, "hip_dy": -4.0, "lean_deg": 4.0, "lf_dx": -24.0, "rf_dx": 22.0, "lh_dx": 20.0, "lh_dy": 20.0, "rh_dx": 24.0, "rh_dy": 12.0, "sword_ang": -52.0, "flare_x": -16.0},
                {"is_moving": True, "hip_dx": 12.0, "hip_dy": 10.0, "lean_deg": 16.0, "lf_dx": -36.0, "rf_dx": 36.0, "lh_dx": 18.0, "lh_dy": 36.0, "rh_dx": 38.0, "rh_dy": 34.0, "sword_ang": -16.0, "flare_x": -26.0},
                {"is_moving": True, "hip_dx": 10.0, "hip_dy": 8.0, "lean_deg": 13.0, "lf_dx": -30.0, "rf_dx": 30.0, "lh_dx": 16.0, "lh_dy": 40.0, "rh_dx": 34.0, "rh_dy": 42.0, "sword_ang": 22.0, "flare_x": -18.0},
                {"hip_dx": 2.0, "hip_dy": 2.0, "lean_deg": 4.0, "lf_dx": -16.0, "rf_dx": 16.0, "lh_dx": 16.0, "lh_dy": 44.0, "rh_dx": 18.0, "rh_dy": 46.0, "sword_ang": 34.0, "flare_x": -6.0},
            ]
        else:
            atk2_list = [
                {"is_moving": True, "hip_dx": -4.0, "hip_dy": 0.0, "lean_deg": -3.0, "lf_dx": -16.0, "rf_dx": 16.0, "lh_dx": -12.0, "lh_dy": 24.0, "le_sign": -1.0, "rh_dx": 16.0, "rh_dy": 22.0, "flare_x": -8.0, "ribbon_lift": 10.0},
                {"is_moving": True, "hip_dx": 6.0, "hip_dy": 4.0, "lean_deg": 8.0, "lf_dx": -26.0, "rf_dx": 26.0, "lh_dx": -26.0, "lh_dy": 16.0, "le_sign": -1.0, "rh_dx": 38.0, "rh_dy": 12.0, "open_palm": True, "flare_x": -20.0, "ribbon_lift": 26.0},
                {"is_moving": True, "hip_dx": 10.0, "hip_dy": 6.0, "lean_deg": 12.0, "lf_dx": -34.0, "rf_dx": 34.0, "lh_dx": -34.0, "lh_dy": 12.0, "le_sign": -1.0, "rh_dx": 46.0, "rh_dy": 10.0, "open_palm": True, "flare_x": -28.0, "ribbon_lift": 34.0},
                {"is_moving": True, "hip_dx": 6.0, "hip_dy": 4.0, "lean_deg": 7.0, "lf_dx": -24.0, "rf_dx": 24.0, "lh_dx": -20.0, "lh_dy": 22.0, "le_sign": -1.0, "rh_dx": 32.0, "rh_dy": 20.0, "open_palm": True, "flare_x": -18.0, "ribbon_lift": 20.0},
                {"hip_dx": 0.0, "hip_dy": 0.0, "lean_deg": 2.0, "lf_dx": -14.0, "rf_dx": 14.0, "lh_dx": 10.0, "lh_dy": 36.0, "rh_dx": 22.0, "rh_dy": 34.0, "flare_x": -6.0, "ribbon_lift": 6.0},
            ]
        for f, p in enumerate(atk2_list):
            put_arr(5, f, render_fixed_combat_hero_cell(aid, rig, p, cw, ch))

        # Row 6: `cast_loop` (0..2) + `cast_release` (3..5)
        for f in range(3):
            ph = (2.0 * math.pi * f) / 3.0
            if not is_shen:
                p_cl = {
                    "hip_dy": -1.5 + 1.0 * math.sin(ph),
                    "lean_deg": 1.0,
                    "lf_dx": -18.0,
                    "rf_dx": 18.0,
                    "lh_dx": 16.0,
                    "lh_dy": 26.0 - 2.0 * math.sin(ph),
                    "rh_dx": 20.0,
                    "rh_dy": 26.0 - 2.0 * math.sin(ph),
                    "sword_ang": -88.0 + 3.0 * math.cos(ph),
                    "flare_x": -10.0 - 4.0 * math.sin(ph),
                }
            else:
                p_cl = {
                    "is_moving": True,
                    "hip_dy": -2.0 + 1.2 * math.sin(ph),
                    "lean_deg": -1.0,
                    "lf_dx": -26.0,
                    "rf_dx": 26.0,
                    "lh_dx": -34.0,
                    "lh_dy": 2.0 - 3.0 * math.sin(ph),
                    "le_sign": -1.0,
                    "rh_dx": 36.0,
                    "rh_dy": 0.0 - 3.0 * math.sin(ph),
                    "open_palm": True,
                    "flare_x": -18.0 - 6.0 * math.sin(ph),
                    "ribbon_lift": 28.0 + 8.0 * math.sin(ph),
                }
            put_arr(6, f, render_fixed_combat_hero_cell(aid, rig, p_cl, cw, ch))

        for idx_cr, f in enumerate([3, 4, 5]):
            if not is_shen:
                p_cr = [
                    {"is_moving": True, "hip_dx": 9.0, "hip_dy": 6.0, "lean_deg": 13.0, "lf_dx": -32.0, "rf_dx": 32.0, "lh_dx": 32.0, "lh_dy": 26.0, "rh_dx": 36.0, "rh_dy": 30.0, "sword_ang": -6.0, "flare_x": -22.0},
                    {"is_moving": True, "hip_dx": 11.0, "hip_dy": 8.0, "lean_deg": 14.0, "lf_dx": -34.0, "rf_dx": 34.0, "lh_dx": 36.0, "lh_dy": 28.0, "rh_dx": 38.0, "rh_dy": 32.0, "sword_ang": 0.0, "flare_x": -24.0},
                    {"hip_dx": 4.0, "hip_dy": 2.0, "lean_deg": 6.0, "lf_dx": -20.0, "rf_dx": 20.0, "lh_dx": 18.0, "lh_dy": 38.0, "rh_dx": 24.0, "rh_dy": 40.0, "sword_ang": 22.0, "flare_x": -10.0},
                ][idx_cr]
            else:
                p_cr = [
                    {"is_moving": True, "hip_dx": 8.0, "hip_dy": 5.0, "lean_deg": 10.0, "lf_dx": -32.0, "rf_dx": 32.0, "lh_dx": -28.0, "lh_dy": 14.0, "le_sign": -1.0, "rh_dx": 44.0, "rh_dy": 10.0, "open_palm": True, "flare_x": -26.0, "ribbon_lift": 32.0},
                    {"is_moving": True, "hip_dx": 10.0, "hip_dy": 6.0, "lean_deg": 11.0, "lf_dx": -34.0, "rf_dx": 34.0, "lh_dx": -22.0, "lh_dy": 18.0, "le_sign": -1.0, "rh_dx": 48.0, "rh_dy": 14.0, "open_palm": True, "flare_x": -28.0, "ribbon_lift": 28.0},
                    {"hip_dx": 2.0, "hip_dy": 1.0, "lean_deg": 4.0, "lf_dx": -18.0, "rf_dx": 18.0, "lh_dx": 8.0, "lh_dy": 34.0, "rh_dx": 26.0, "rh_dy": 30.0, "flare_x": -10.0, "ribbon_lift": 12.0},
                ][idx_cr]
            put_arr(6, f, render_fixed_combat_hero_cell(aid, rig, p_cr, cw, ch))

        # Row 7: `hit` (0..1) + `down` (2..3)
        hit_down_list = [
            {"hip_dx": -10.0, "hip_dy": 4.0, "lean_deg": -12.0, "head_ang": -8.0, "lf_dx": -22.0, "rf_dx": 12.0, "lh_dx": 10.0, "lh_dy": 30.0, "rh_dx": 12.0, "rh_dy": 38.0, "sword_ang": -38.0, "flare_x": 12.0, "ribbon_lift": 16.0},
            {"hip_dx": -6.0, "hip_dy": 2.0, "lean_deg": -8.0, "head_ang": -5.0, "lf_dx": -18.0, "rf_dx": 14.0, "lh_dx": 12.0, "lh_dy": 36.0, "rh_dx": 14.0, "rh_dy": 42.0, "sword_ang": -28.0, "flare_x": 8.0, "ribbon_lift": 10.0},
            {"is_down": True, "hip_dx": -6.0, "hip_dy": 42.0, "lean_deg": 32.0, "head_dx": 6.0, "head_ang": 10.0, "lf_dx": -34.0, "lf_dy": 2.0, "rf_dx": 14.0, "rf_dy": 2.0, "lh_dx": 12.0, "lh_dy": 42.0, "rh_dx": 22.0, "rh_dy": 46.0, "sword_ang": 12.0, "flare_x": -12.0},
            {"is_down": True, "hip_dx": -4.0, "hip_dy": 48.0, "lean_deg": 40.0, "head_dx": 8.0, "head_ang": 14.0, "lf_dx": -36.0, "lf_dy": 2.0, "rf_dx": 16.0, "rf_dy": 2.0, "lh_dx": 14.0, "lh_dy": 44.0, "rh_dx": 24.0, "rh_dy": 48.0, "sword_ang": 8.0, "flare_x": -14.0},
        ]
        for f, p in enumerate(hit_down_list):
            put_arr(7, f, render_fixed_combat_hero_cell(aid, rig, p, cw, ch))

        assert count_fluorescent_pixels(sheet) == 0, f"Fluorescent pixels in {aid}_sheet.png"
        # Verify T4-W2-03 >= 1.28x multi-pose attack width extension gate at build time!
        idle_w = max(
            int(np.ptp(np.where(sheet[0:ch, f * cw : (f + 1) * cw, 3] > 0)[1])) + 1 for f in range(4)
        )
        atk1_w = max(
            int(np.ptp(np.where(sheet[4 * ch : 5 * ch, f * cw : (f + 1) * cw, 3] > 0)[1])) + 1 for f in range(5)
        )
        ext_ratio = float(atk1_w) / float(max(1, idle_w))
        assert ext_ratio >= 1.35, f"{aid} attack_1 width ratio {ext_ratio:.3f} < 1.35"

        # Verify T1-F06-05 ground contact invariant (`foot_y - 10 <= contact_y <= cell_h - 1`)
        for r_chk, cnt_chk in [(0, 4), (2, 6)]:
            for f_c in range(cnt_chk):
                ys_c = np.where(sheet[r_chk * ch : (r_chk + 1) * ch, f_c * cw : (f_c + 1) * cw, 3] > 0)[0]
                c_y = int(ys_c.max())
                assert foot_y - 8 <= c_y <= ch - 1, f"{aid} row {r_chk} col {f_c} contact_y={c_y} out of range!"

        rel_png = f"project/assets/sprites/{aid}_sheet.png"
        r2_act.save_rgba_clean(sheet, os.path.join(REPO_ROOT, rel_png))

        # Update run_se / run_ne weapon anchor (+X forward carry instead of -38 backward!)
        json_p = os.path.join(REPO_ROOT, f"project/assets/sprites/{aid}_sheet.json")
        with open(json_p, "r", encoding="utf-8") as jfh:
            jdoc = json.load(jfh)
        if not is_shen and "state_anchors" in jdoc:
            for rk in ("run_se", "run_ne"):
                if rk in jdoc["state_anchors"]:
                    jdoc["state_anchors"][rk]["weapon"] = [36, -64]
        with open(json_p, "w", encoding="utf-8") as jfh:
            json.dump(jdoc, jfh, indent=2)
            jfh.write("\n")

        updates.append(
            {
                "path": rel_png,
                "source_path": "assets_src/sprites/r2_party_parts_sheet.png",
                "category": "sprite_sheet",
                "creation_method": (
                    f"Gemini Imagen (2026-11-28, Song-Ming Gongbi 3/4 character sheets char_ref_party_pets_raw.jpg, "
                    f"char_ref_party_back_raw.jpg & r2_party_parts_sheet.png) + tools/build_polish_r6_actors_and_town.py "
                    f"canonical SE/NE idle + 2-bone scissor-stride run + anatomical martial combat rig ({aid})"
                ),
                "license": LIC_R6,
            }
        )
    return updates


# ==================== 2. GROUND-PLANTED SHADOW-FREE NPC / PET / ENEMY SHEETS ====================
def strip_bottom_studio_cast_shadow(im_rgba: Image.Image, y_start_frac: float = 0.82) -> Image.Image:
    """
    Removes residual warm-beige studio floor cast-shadows painted between enemy feet/paws/staves
    strictly via 4-connected exterior flood-fill (`cv2.connectedComponents`) blocked by dark Gongbi ink
    contours (`luma < 95`), touching ZERO interior clothing hems or stone armor plates!
    """
    arr = np.asarray(im_rgba, dtype=np.uint8).copy()
    h, w, _ = arr.shape
    rgb = arr[..., :3].astype(np.float32)
    luma = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]
    chroma = rgb.max(axis=-1) - rgb.min(axis=-1)

    y0 = int(round(h * y_start_frac))
    yy = np.arange(h)[:, None]
    ink_barrier = (arr[..., 3] >= 40) & (luma < 95.0)
    seed = (
        cv2.dilate((arr[..., 3] < 20).astype(np.uint8), np.ones((5, 5), np.uint8), iterations=1).astype(bool)
        & (~ink_barrier)
    )
    cand = seed | (
        (yy >= y0)
        & (~ink_barrier)
        & (luma >= 128.0)
        & (chroma <= 38.0)
        & ((rgb[..., 0] - rgb[..., 2]) >= 6.0)
    )
    _, labels = cv2.connectedComponents(cand.astype(np.uint8), connectivity=4)
    ext_labels = set(np.unique(labels[seed]))
    pale_floor = (
        np.isin(labels, list(ext_labels))
        & (arr[..., 3] >= 20)
        & (yy >= y0)
        & (luma >= 122.0)
        & (chroma <= 38.0)
    )
    arr[pale_floor, 3] = 0
    arr = r2_act.prune_tiny_alpha_specks(r2_act.clean_zero_alpha(arr), max_speck_area=18, alpha_thresh=14)

    ys, xs = np.where(arr[..., 3] > 14)
    if len(xs) == 0:
        return Image.fromarray(arr, mode="RGBA")
    return Image.fromarray(
        arr[int(ys.min()) : int(ys.max()) + 1, int(xs.min()) : int(xs.max()) + 1],
        mode="RGBA",
    )


def render_grounded_shadowfree_frame(
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
    """
    Replaces `build_r2_polish_assets.render_clean_frame`:
    - ZERO baked floor shadow oval inside sprite cells (uses `BattleActor._draw()`'s dynamic shadow!).
    - Pads `src` by `pad = 28px` transparent margin on all 4 sides BEFORE `cv2.remap` so hats, foreheads,
      snouts, staves, and tails NEVER slice flat against tight-crop borders!
    - Anchors `shoe_y` 100.0% flush on `foot_y` (`0px` levitation) and lifts passing legs UPWARD (`dy -= ...`)
      during `run` while keeping stance feet planted on `foot_y`!
    """
    src0 = np.asarray(fig_rgba, dtype=np.float32)
    sh0, sw0, _ = src0.shape

    if is_enemy and state == "hit_down" and frame_idx >= 2:
        collapsed_h = max(20, int(round(sh0 * 0.46)))
        rot_im = fig_rgba.rotate(-74 if is_quadruped else -80, expand=True, resample=Image.Resampling.BICUBIC)
        ys, xs = np.where(np.asarray(rot_im)[..., 3] > 16)
        if len(xs) > 0:
            rot_im = rot_im.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))
        rot_im = rot_im.resize(
            (min(cell_w - 18, rot_im.width), min(collapsed_h + 18, rot_im.height)),
            Image.Resampling.LANCZOS,
        )
        r_arr = np.asarray(rot_im, dtype=np.float32)
        fade = 0.72 if frame_idx == 2 else 0.50
        r_arr[..., :3] *= np.array([0.58, 0.52, 0.62], dtype=np.float32)
        r_arr[..., 3] *= fade
        canvas = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
        px = (cell_w - rot_im.width) // 2
        py = foot_y - rot_im.height + 2
        canvas.alpha_composite(Image.fromarray(np.clip(r_arr, 0, 255).astype(np.uint8), mode="RGBA"), (px, py))
        return canvas

    pad = 28
    src = np.pad(src0, ((pad, pad), (pad, pad), (0, 0)), mode="constant", constant_values=0.0)
    sh, sw, _ = src.shape

    yy, xx = np.meshgrid(np.arange(sh, dtype=np.float32), np.arange(sw, dtype=np.float32), indexing="ij")
    # Normalize `yn` & `xn` over the unpadded character body `[pad .. pad + sh0 - 1]`!
    yn = np.clip((yy - pad) / max(1.0, float(sh0 - 1)), -0.35, 1.35)
    xn = np.clip((xx - pad) / max(1.0, float(sw0 - 1)), -0.35, 1.35) - 0.5

    phase = (2.0 * math.pi * frame_idx) / max(1, total_frames)
    dx = np.zeros_like(xx)
    dy = np.zeros_like(yy)

    upper_w = np.clip((0.48 - yn) / 0.34, 0.0, 1.0)
    lower_w = np.clip((yn - 0.54) / 0.44, 0.0, 1.0)
    left_side = np.clip((-xn + 0.03) * 5.5, 0.0, 1.0)
    right_side = np.clip((xn + 0.03) * 5.5, 0.0, 1.0)
    sleeve_w = np.clip((yn - 0.25) / 0.30, 0.0, 1.0) * np.clip((0.72 - yn) / 0.18, 0.0, 1.0)

    lunge_px = 0.0
    tint_mult = np.array([1.0, 1.0, 1.0], dtype=np.float32)

    if state == "idle":
        # Calm dignified chest-only micro-breath; waist-to-shoes 100% locked on ground!
        breath = math.sin(phase)
        dy -= upper_w * (0.85 * breath)
        dx += sleeve_w * (0.75 * math.cos(phase))
    elif state == "run":
        # Stance-planted alternating leg stride: ONLY the passing leg lifts UPWARD (`dy -= ...` shifts pixels to `-Y`),
        # while the stance leg (`max == 0`) stays 100% planted on `foot_y`!
        stride = math.sin(phase)
        leg_amp = 10.5 if not is_quadruped else 12.5
        lift_amp = 7.0 if not is_quadruped else 6.0
        dx += lower_w * (left_side * stride * leg_amp - right_side * stride * leg_amp)
        dy -= lower_w * (left_side * max(0.0, -stride) * lift_amp + right_side * max(0.0, stride) * lift_amp)
        dx += upper_w * (3.2 + 2.2 * math.cos(phase))
        dy += upper_w * (1.2 * abs(math.sin(phase)))
    elif state == "attack_1":
        curves = [-7.0, 12.0, 15.0, 8.0, 2.0]
        rot_deg = [-5.0, 8.0, 10.0, 4.0, 0.0]
        lunge_px = curves[min(frame_idx, 4)]
        ang = math.radians(rot_deg[min(frame_idx, 4)])
        cx0, cy0 = pad + sw0 * 0.5, pad + sh0 * 0.72
        rx = (xx - cx0) * math.cos(ang) - (yy - cy0) * math.sin(ang) + cx0 - xx
        ry = (xx - cx0) * math.sin(ang) + (yy - cy0) * math.cos(ang) + cy0 - yy
        dx += upper_w * (rx + lunge_px * 0.4)
        dy += upper_w * ry
    elif state == "attack_2":
        curves = [-5.0, -2.0, 14.0, 11.0, 2.0]
        lunge_px = curves[min(frame_idx, 4)]
        dy -= upper_w * (5.0 if frame_idx in (1, 2) else 0.0)
        dx += upper_w * (lunge_px * 0.45)
    elif state == "cast":
        if frame_idx < 3:
            pulse = math.sin(frame_idx * 1.6)
            dy -= upper_w * (2.6 + 1.4 * pulse)
            dx += sleeve_w * (2.5 * math.cos(frame_idx * 2.0))
        else:
            lunge_px = 8.0 if frame_idx == 3 else (5.0 if frame_idx == 4 else 1.5)
            dx += upper_w * 4.0
    elif state == "hit_down":
        if frame_idx < 2:
            recoil = -8.5 if frame_idx == 0 else -4.5
            lunge_px = recoil
            dx += upper_w * recoil * 0.55
            dy += upper_w * 2.5
            tint_mult = (
                np.array([1.18, 0.90, 0.88], dtype=np.float32)
                if frame_idx == 0
                else np.array([1.06, 0.95, 0.95], dtype=np.float32)
            )
        else:
            kneel_drop = 0.22 if frame_idx == 2 else 0.26
            dy += np.clip(1.0 - yn, 0.0, 1.0) * sh0 * kneel_drop
            dx += upper_w * 6.5
            tint_mult = np.array([0.82, 0.80, 0.82], dtype=np.float32)

    warped = cv2.remap(
        src,
        (xx - dx).astype(np.float32),
        (yy - dy).astype(np.float32),
        interpolation=cv2.INTER_LINEAR,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=(0, 0, 0, 0),
    )
    warped[..., :3] = np.clip(warped[..., :3] * tint_mult[None, None, :], 0, 255)
    w_u8 = clamp_song_ming_mineral_hsv(np.clip(warped, 0, 255).astype(np.uint8))
    w_u8[w_u8[..., 3] < 10] = 0

    # Composite padded warped image onto cell_w x cell_h with 2px inner anti-clipping border guard
    canvas_arr = np.zeros((cell_h, cell_w, 4), dtype=np.uint8)
    paste_x = int(round((cell_w - sw0) * 0.5 - pad + lunge_px))
    paste_y = int(round(foot_y - (shoe_y + pad)))

    x0_d = max(2, paste_x)
    y0_d = max(2, paste_y)
    x1_d = min(cell_w - 2, paste_x + sw)
    y1_d = min(cell_h - 2, paste_y + sh)
    if x1_d > x0_d and y1_d > y0_d:
        x0_s = x0_d - paste_x
        y0_s = y0_d - paste_y
        r2_act.alpha_over_np(
            canvas_arr[y0_d:y1_d, x0_d:x1_d],
            w_u8[y0_s : y0_s + (y1_d - y0_d), x0_s : x0_s + (x1_d - x0_d)],
        )
    canvas_arr[foot_y + 4 :, :, :] = 0
    return Image.fromarray(r2_act.clean_zero_alpha(canvas_arr), mode="RGBA")


def build_grounded_actor_sheet(
    actor_id: str,
    front_im: Image.Image,
    back_im: Image.Image,
    target_h: int,
    cell_w: int,
    cell_h: int,
    accent_rgb: tuple[int, int, int],
    source_rel: str,
    is_quadruped: bool = False,
    is_enemy: bool = False,
) -> dict[str, str]:
    def prep_scaled(im: Image.Image) -> tuple[Image.Image, int]:
        cleaned = strip_bottom_studio_cast_shadow(im, y_start_frac=0.82) if is_enemy else im
        sc = target_h / float(max(1, cleaned.height))
        max_w = int(cell_w * 0.76)
        nw = min(max_w, max(24, int(round(cleaned.width * sc))))
        nh = int(round(cleaned.height * (nw / float(max(1, cleaned.width)))))
        resized = crisp_resize_rgba(cleaned, nw, nh, unsharp_pct=38)
        return trim_stick_overhang_below_shoe(resized, min_span_px=6 if not is_quadruped else 4)

    f_scaled, f_shoe_y = prep_scaled(front_im)
    b_scaled, b_shoe_y = prep_scaled(back_im)
    foot_y = cell_h - 22

    sheet = Image.new("RGBA", (cell_w * 6, cell_h * 8), (0, 0, 0, 0))
    row_specs = [
        (0, f_scaled, f_shoe_y, "idle", 4),
        (1, b_scaled, b_shoe_y, "idle", 4),
        (2, f_scaled, f_shoe_y, "run", 6),
        (3, b_scaled, b_shoe_y, "run", 6),
        (4, f_scaled, f_shoe_y, "attack_1", 5),
        (5, f_scaled, f_shoe_y, "attack_2", 5),
        (6, f_scaled, f_shoe_y, "cast", 6),
        (7, f_scaled, f_shoe_y, "hit_down", 4),
    ]
    for row_idx, s_fig, s_y, st_name, f_cnt in row_specs:
        for col_idx in range(f_cnt):
            cell = render_grounded_shadowfree_frame(
                s_fig, s_y, cell_w, cell_h, foot_y, st_name, col_idx, f_cnt, accent_rgb, is_quadruped, is_enemy
            )
            sheet.paste(cell, (col_idx * cell_w, row_idx * cell_h))

    sh_arr = clamp_song_ming_mineral_hsv(np.asarray(sheet, dtype=np.uint8))
    assert count_fluorescent_pixels(sh_arr) == 0, f"Fluorescent pixels in {actor_id}_sheet.png"
    out_rel = f"project/assets/sprites/{actor_id}_sheet.png"
    r2_act.save_rgba_clean(sh_arr, os.path.join(REPO_ROOT, out_rel))

    json_p = os.path.join(REPO_ROOT, f"project/assets/sprites/{actor_id}_sheet.json")
    meta: dict[str, Any] = {}
    if os.path.isfile(json_p):
        with open(json_p, "r", encoding="utf-8") as fh:
            meta = json.load(fh)
    meta.update(
        {
            "actor_id": actor_id,
            "cell_w": cell_w,
            "cell_h": cell_h,
            "foot_y": foot_y,
            "head_top_px": max(72, f_shoe_y + 8),
            "cols": 6,
            "rows": {
                "idle_se": {"row": 0, "frames": 4, "fps": 5.5, "loop": True},
                "idle_ne": {"row": 1, "frames": 4, "fps": 5.5, "loop": True},
                "run_se": {"row": 2, "frames": 6, "fps": 10.5, "loop": True},
                "run_ne": {"row": 3, "frames": 6, "fps": 10.5, "loop": True},
                "attack_1": {"row": 4, "frames": 5, "fps": 11.0, "loop": False},
                "attack_2": {"row": 5, "frames": 5, "fps": 11.0, "loop": False},
                "cast_loop": {"row": 6, "start_col": 0, "frames": 3, "fps": 7.0, "loop": True},
                "cast_release": {"row": 6, "start_col": 3, "frames": 3, "fps": 10.0, "loop": False},
                "hit": {"row": 7, "start_col": 0, "frames": 2, "fps": 9.0, "loop": False},
                "down": {"row": 7, "start_col": 2, "frames": 2, "fps": 4.0, "loop": False},
            },
        }
    )
    with open(json_p, "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2)
        fh.write("\n")

    return {
        "path": out_rel,
        "source_path": source_rel,
        "category": "sprite_sheet",
        "creation_method": (
            f"Gemini Imagen (2026-11-28, Song-Ming Gongbi reference {source_rel}) + "
            f"tools/build_polish_r6_actors_and_town.py 28px-padded shadow-free shoe-sole grounded keyframe sheet ({actor_id})"
        ),
        "license": LIC_R6,
    }


def build_all_grounded_npcs_pets_enemies() -> list[dict[str, str]]:
    updates: list[dict[str, str]] = []

    # 1. Town NPCs: npc_elder & npc_steward_zhou from char_ref_town_npcs_raw.jpg
    tn_src = "assets_src/sprites/char_ref_town_npcs_raw.jpg"
    elder_fig, zhou_fig = isolate_sheet_components(
        os.path.join(REPO_ROOT, tn_src), 2, shadow_y_start=645, strip_enclosed_cream=True
    )
    updates.append(
        build_grounded_actor_sheet(
            "npc_elder",
            elder_fig,
            build_back_silhouette_fallback(elder_fig),
            154,
            224,
            224,
            (156, 138, 102),
            tn_src,
        )
    )
    updates.append(
        build_grounded_actor_sheet(
            "npc_steward_zhou",
            zhou_fig,
            build_back_silhouette_fallback(zhou_fig),
            158,
            224,
            224,
            (132, 128, 108),
            tn_src,
        )
    )

    # 2. Peddler NPC from prop_peddler_and_yaolu_raw.jpg
    ped_src = "assets_src/world/prop_peddler_and_yaolu_raw.jpg"
    ped_fig, _, _ = isolate_sheet_components(
        os.path.join(REPO_ROOT, ped_src), 3, shadow_y_start=690, strip_enclosed_cream=True
    )
    updates.append(
        build_grounded_actor_sheet(
            "npc_peddler",
            ped_fig,
            build_back_silhouette_fallback(ped_fig),
            158,
            224,
            224,
            (172, 148, 102),
            ped_src,
        )
    )

    # 3. Spirit Pets: pet_fire_fox & pet_spirit_turtle
    pf_src = "assets_src/sprites/char_ref_party_pets_raw.jpg"
    pb_src = "assets_src/sprites/char_ref_party_back_raw.jpg"
    pf_figs = isolate_sheet_components(os.path.join(REPO_ROOT, pf_src), 5, shadow_y_start=640, strip_enclosed_cream=False)
    pb_figs = isolate_sheet_components(os.path.join(REPO_ROOT, pb_src), 5, shadow_y_start=640, strip_enclosed_cream=False)
    updates.append(
        build_grounded_actor_sheet(
            "pet_fire_fox", pf_figs[3], pb_figs[3], 90, 192, 176, (198, 76, 52), pf_src, is_quadruped=True
        )
    )
    updates.append(
        build_grounded_actor_sheet(
            "pet_spirit_turtle", pf_figs[4], pb_figs[4], 78, 208, 176, (72, 142, 168), pf_src, is_quadruped=True
        )
    )

    # 4. Non-Boss Enemies (`boss_mist_wolf_king` kept untouched at M2 giant rig!)
    # Native facing in `char_ref_enemies_boss_raw.jpg` is ALREADY `+X` (right/SE), matching `BattleActor.flip_h = facing_dir.x < -0.08`!
    ef_src = "assets_src/sprites/char_ref_enemies_boss_raw.jpg"
    ef_figs = isolate_sheet_components(os.path.join(REPO_ROOT, ef_src), 5, shadow_y_start=520, strip_enclosed_cream=True)
    enemy_specs = [
        ("enemy_rot_wolf", ef_figs[0], 112, 256, 192, (132, 68, 146), True),
        ("enemy_miasma_shaman", ef_figs[1], 148, 224, 224, (96, 152, 92), False),
        ("enemy_rogue_cultivator", ef_figs[2], 156, 240, 224, (168, 188, 205), False),
        ("enemy_wood_golem", ef_figs[3], 196, 272, 264, (112, 156, 88), False),
    ]
    for eid, efig, th, cw, ch, acc, is_q in enemy_specs:
        f_right = efig
        b_right = build_back_silhouette_fallback(f_right)
        updates.append(
            build_grounded_actor_sheet(eid, f_right, b_right, th, cw, ch, acc, ef_src, is_quadruped=is_q, is_enemy=True)
        )

    return updates


# ==================== 3. TOWN WORLD PROPS REFINEMENT ====================
def build_r6_town_world_props() -> list[dict[str, str]]:
    updates: list[dict[str, str]] = []

    # A. NE-facing South-Street Jiangnan Folk Houses (`prop_folk_roof_eave.png` & `prop_folk_house_south.png`)
    sf_src = "assets_src/world/r6_south_folk_houses_raw.jpg"
    im_sf = np.asarray(Image.open(os.path.join(REPO_ROOT, sf_src)).convert("RGB"))
    bg_sf = np.median(im_sf[:20, :, :], axis=(0, 1))

    south_a_cut = extract_exterior_cutout(im_sf[68:642, 60:660], bg_sf, tol=21.0)
    # Clear tiny cream opening under right cottage's NW wooden porch roof (`x=0..95, y=170..330` in sub-crop)
    south_b_cut = extract_exterior_cutout(
        im_sf[124:638, 744:1314], bg_sf, tol=21.0, extra_hole_boxes=[(0, 165, 110, 355)]
    )

    eave_rel = "project/assets/world/prop_folk_roof_eave.png"
    save_grounded_rgba(south_a_cut, 296, 274, eave_rel, shadow_alpha=78, pad_bot=4, lut_sat=0.92)
    updates.append(
        {
            "path": eave_rel,
            "source_path": sf_src,
            "category": "world_prop",
            "creation_method": (
                "Gemini Imagen (2026-11-28, prompt: '35-degree isometric Song-Ming Gongbi Jiangnan white-wall "
                "dark-tile folk houses facing northeast toward street, stepped Matouqiang gable walls, cream studio "
                "background, no text') + tools/build_polish_r6_actors_and_town.py cutout & mineral palette LUT"
            ),
            "license": LIC_R6,
        }
    )

    south_rel = "project/assets/world/prop_folk_house_south.png"
    save_grounded_rgba(south_b_cut, 276, 268, south_rel, shadow_alpha=78, pad_bot=4, lut_sat=0.92)
    updates.append(
        {
            "path": south_rel,
            "source_path": sf_src,
            "category": "world_prop",
            "creation_method": (
                "Gemini Imagen (2026-11-28, prompt: '35-degree isometric Song-Ming Gongbi Jiangnan white-wall "
                "dark-tile folk houses facing northeast toward street, stepped Matouqiang gable walls, wooden porch "
                "& bamboo awning, cream studio background') + tools/build_polish_r6_actors_and_town.py cutout & LUT"
            ),
            "license": LIC_R6,
        }
    )

    # B. Clean `prop_bamboo_cluster.png` (zero cream/grey blotches between stalks & leaves!)
    fol_src = "assets_src/world/prop_sheet_foliage_raw.jpg"
    im_fol = np.asarray(Image.open(os.path.join(REPO_ROOT, fol_src)).convert("RGB"))
    bg_fol = np.median(im_fol[:20, :, :], axis=(0, 1))
    bam_sub = im_fol[98:658, 550:908].copy()
    bh_s, bw_s, _ = bam_sub.shape
    diff_b = np.linalg.norm(bam_sub.astype(np.float32) - bg_fol[None, None, :], axis=-1)
    luma_b = (
        0.299 * bam_sub[..., 0].astype(np.float32)
        + 0.587 * bam_sub[..., 1].astype(np.float32)
        + 0.114 * bam_sub[..., 2].astype(np.float32)
    )
    green_ex = bam_sub[..., 1].astype(np.float32) - 0.5 * (
        bam_sub[..., 0].astype(np.float32) + bam_sub[..., 2].astype(np.float32)
    )
    yy_b = np.arange(bh_s)[:, None]
    canopy_pocket = (yy_b < int(bh_s * 0.74)) & ((diff_b < 46.0) | ((luma_b > 152.0) & (green_ex < 22.0)))
    bam_sub[canopy_pocket] = bg_fol.astype(np.uint8)
    bam_cut = extract_exterior_cutout(
        bam_sub, bg_fol, tol=25.0, extra_hole_boxes=[(0, 0, bw_s, int(bh_s * 0.76))]
    )
    bam_rel = "project/assets/world/prop_bamboo_cluster.png"
    save_grounded_rgba(bam_cut, 178, 290, bam_rel, shadow_alpha=80, pad_bot=4, lut_sat=0.90)
    updates.append(
        {
            "path": bam_rel,
            "source_path": fol_src,
            "category": "world_ysort_foliage",
            "creation_method": (
                "Gemini Imagen (2026-11-28, prop_sheet_foliage_raw.jpg Song-Ming Gongbi emerald bamboo cluster) + "
                "tools/build_polish_r6_actors_and_town.py full interior canopy pocket cutout & ink-jade defringe"
            ),
            "license": LIC_R6,
        }
    )

    # C. High-contrast enlarged `'济世药庐'` plaque on `prop_yaolu_gatehouse.png` for `1024x553` legibility
    gp_src = "assets_src/world/r5_yaolu_gate_pavilion_raw.jpg"
    im_gp = np.asarray(Image.open(os.path.join(REPO_ROOT, gp_src)).convert("RGB"))
    bg_gp = np.median(im_gp[:20, :, :], axis=(0, 1))
    gate_cut = extract_exterior_cutout(
        im_gp[140:610, 48:485], bg_gp, tol=19.5, extra_hole_boxes=[(175, 180, 286, 382), (80, 110, 185, 225)]
    )
    from PIL import ImageOps

    gate_sw = ImageOps.mirror(gate_cut)
    gate_rel = "project/assets/world/prop_yaolu_gatehouse.png"
    gate_arr = save_grounded_rgba(gate_sw, 268, 284, gate_rel, shadow_alpha=76, pad_bot=4, lut_sat=0.92)
    gate_im = Image.fromarray(gate_arr, mode="RGBA")
    plaque_card = build_isometric_carved_plaque("济世药庐", w_px=29, vert_h=56, shear_y_per_x=0.48)
    gate_im.alpha_composite(plaque_card, (37, 96))
    gate_arr = clamp_song_ming_mineral_hsv(np.asarray(gate_im, dtype=np.uint8))
    assert count_fluorescent_pixels(gate_arr) == 0, "Fluorescent pixels in prop_yaolu_gatehouse.png"
    Image.fromarray(gate_arr, mode="RGBA").save(os.path.join(REPO_ROOT, gate_rel), format="PNG", optimize=False)
    updates.append(
        {
            "path": gate_rel,
            "source_path": gp_src,
            "category": "world_prop",
            "creation_method": (
                "Gemini Imagen (2026-11-28, r5_yaolu_gate_pavilion_raw.jpg 35-deg Song-Ming Gongbi white-wall "
                "pharmacy gatehouse) + tools/build_polish_r6_actors_and_town.py SW alignment & enlarged '济世药庐' plaque"
            ),
            "license": LIC_R6,
        }
    )

    return updates


def main() -> None:
    all_updates: list[dict[str, str]] = []
    all_updates.extend(build_r6_party_hero_sheets())
    all_updates.extend(build_all_grounded_npcs_pets_enemies())
    all_updates.extend(build_r6_town_world_props())

    manifest_path = os.path.join(REPO_ROOT, "docs/asset-manifest.json")
    with open(manifest_path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)
    by_path: dict[str, dict[str, Any]] = {str(e["path"]): e for e in doc.get("assets", [])}

    for m in all_updates:
        rel_p = m["path"]
        full_p = os.path.join(REPO_ROOT, rel_p)
        with Image.open(full_p) as im_chk:
            dims = f"{im_chk.width}x{im_chk.height}"
        by_path[rel_p] = {
            "path": rel_p,
            "source_path": m["source_path"],
            "category": m["category"],
            "dimensions": dims,
            "sha256": sha256_file(full_p),
            "creation_method": m["creation_method"],
            "generated_date": GEN_DATE,
            "license": m["license"],
        }

    doc["assets"] = [by_path[k] for k in sorted(by_path.keys())]
    with open(manifest_path, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False, indent=2)
        fh.write("\n")

    print(
        f"[build_polish_r6_actors_and_town] Built & verified {len(all_updates)} R6 assets cleanly "
        f"(manifest={len(doc['assets'])}, 0 neon px, 0 baked shadows, >=1.35x lunge width)."
    )


if __name__ == "__main__":
    main()
