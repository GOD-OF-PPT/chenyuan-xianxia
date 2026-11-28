#!/usr/bin/env python3
"""
Polish R8 Natural Grounded Gait, Cohesive Weapon Combos, Jiangnan Town Enrichment & Unified Xuan HUD Icons Builder
for 《尘缘问道》 (v0.1.8-slice).

1. Rebuilds all 3 playable hero sprite sheets (`gu_changqing`, `pei_zhao`, `shen_qinghe`) with:
   - True multi-pose grounded Song-Ming Gongbi walking/brisk-striding cycles (`lower_tuck_px = 0.0`, `scale_x = 1.0` —
     ZERO horizontal squishing or needle-cone skirt pinching!),
   - Zero white paper speck behind Gu Changqing's topknot bun,
   - 100% weapon continuity across all 8 rows (Pei Zhao carries his ornate bronze-gold broadsword in every row;
     Gu Changqing wields his uncut straight jian across chamber, cleave, thrust, and seal),
   - Genuine 3-to-4-pose martial/spell combos instead of static single-frame translation.
2. Upgrades `enemy_rot_wolf`, `enemy_wood_golem`, `enemy_miasma_shaman`, `enemy_rogue_cultivator`, and `pet_fire_fox`
   with genuine second hand-painted Song-Ming Gongbi lunge/stride keyframes from `r8_enemies_fox_multipose_raw.jpg`.
3. Builds rich Jiangnan town & pharmacy courtyard assets (`tex_moss_earth.png`, `prop_folk_house_c.png`,
   `prop_yaolu_drying_rack.png`, `prop_town_fence_vignette.png`, `prop_town_garden_patch.png`).
4. Builds unified warm Xuan-parchment `96x96` HUD icons (`sk_metal_sword.png`, `sk_interrupt_seal.png`,
   `sk_lotus_shield.png`, `hud_formation_bagua.png`) matching slots 2–4 & 5–6.
5. Updates `docs/asset-manifest.json` with exact SHA-256 and provenance.
"""

from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
if str(REPO_ROOT / "tools") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "tools"))

import build_polish_r2_actors as r2_act
import build_polish_r5_town as r5_town
import build_polish_r6_actors_and_town as r6_act
import build_polish_r7_combat_and_cave as r7_cave
from build_r2_polish_assets import isolate_sheet_components
from tools.e2e.visual_master_inspector import analyze_sprite_sheet_cells, count_fluorescent_pixels

LIC_R8 = "Original project artwork generated & hand-refined for Chenyuan Wen Dao (Proprietary, all rights reserved)"


def extract_pose(
    im_rgb: np.ndarray,
    crop_box: tuple[int, int, int, int],
    bg_rgb: np.ndarray,
    tol: float = 21.0,
    pockets: list[tuple[float, float, float, float]] | None = None,
) -> Image.Image:
    return r7_cave.extract_clean_gongbi_pose(
        im_rgb,
        crop_box,
        bg_rgb,
        tol=tol,
        pocket_boxes_norm=pockets,
    )


def build_r8_party_hero_sheets() -> list[dict[str, str]]:
    cw, ch, cols, rows_cnt = 352, 280, 6, 8
    foot_y = 248

    # Canonical standing poses (Rows 0 & 1)
    pf_src = REPO_ROOT / "assets_src/sprites/char_ref_party_pets_raw.jpg"
    pb_src = REPO_ROOT / "assets_src/sprites/char_ref_party_back_raw.jpg"
    im_pf_rgb = np.asarray(Image.open(pf_src).convert("RGB"), dtype=np.float32)
    im_pb_rgb = np.asarray(Image.open(pb_src).convert("RGB"), dtype=np.float32)
    bg_pf = np.median(im_pf_rgb[:20, :, :], axis=(0, 1))
    bg_pb = np.median(im_pb_rgb[:20, :, :], axis=(0, 1))

    pf_figs = isolate_sheet_components(str(pf_src), 5, shadow_y_start=640, strip_enclosed_cream=False)
    pb_figs = isolate_sheet_components(str(pb_src), 5, shadow_y_start=640, strip_enclosed_cream=False)

    gu_idle_se = r6_act.punch_specific_cream_pockets(
        pf_figs[0], bg_pf, [(0.12, 0.42, 0.34, 0.62), (0.32, 0.04, 0.56, 0.22)], tol=26.0
    )
    shen_idle_se = pf_figs[1]

    gu_idle_ne = r6_act.punch_specific_cream_pockets(
        pb_figs[0], bg_pb, [(0.08, 0.42, 0.28, 0.62), (0.72, 0.42, 0.92, 0.64)], tol=26.0
    )
    shen_idle_ne = pb_figs[1]
    pei_idle_ne_raw = r6_act.punch_specific_cream_pockets(pb_figs[2], bg_pb, [(0.48, 0.46, 0.68, 0.66)], tol=25.0)

    # Tint Pei Zhao's back-idle blade from cool silver to warm antique bronze-gold so Row 1 matches his bronze broadsword!
    pei_ne_arr = np.asarray(pei_idle_ne_raw, dtype=np.float32).copy()
    h_ne, w_ne, _ = pei_ne_arr.shape
    yy_n, xx_n = np.meshgrid(np.arange(h_ne), np.arange(w_ne), indexing="ij")
    blade_mask = (xx_n > w_ne * 0.54) & (yy_n < h_ne * 0.66) & (pei_ne_arr[..., 3] > 20)
    luma_b = (0.299 * pei_ne_arr[..., 0] + 0.587 * pei_ne_arr[..., 1] + 0.114 * pei_ne_arr[..., 2]) / 255.0
    pei_ne_arr[blade_mask, 0] = np.clip(luma_b[blade_mask] * 212.0 + 18.0, 0, 235)
    pei_ne_arr[blade_mask, 1] = np.clip(luma_b[blade_mask] * 168.0 + 12.0, 0, 195)
    pei_ne_arr[blade_mask, 2] = np.clip(luma_b[blade_mask] * 102.0 + 8.0, 0, 132)
    pei_idle_ne = Image.fromarray(pei_ne_arr.astype(np.uint8), mode="RGBA")

    # R7 multi-pose action plates (with hair-bun cream pocket punched cleanly on Gu!)
    im_gu_r7 = np.asarray(Image.open(REPO_ROOT / "assets_src/sprites/r7_gu_multipose_raw.jpg").convert("RGB"))
    im_ps_r7 = np.asarray(Image.open(REPO_ROOT / "assets_src/sprites/r7_pei_shen_multipose_raw.jpg").convert("RGB"))
    im_tb_r7 = np.asarray(Image.open(REPO_ROOT / "assets_src/sprites/r7_gu_thrust_backrun_raw.jpg").convert("RGB"))
    bg_gu7 = np.median(im_gu_r7[:18, :18, :].astype(np.float32), axis=(0, 1))
    bg_ps7 = np.median(im_ps_r7[:18, :18, :].astype(np.float32), axis=(0, 1))
    bg_tb7 = np.median(im_tb_r7[:18, :18, :].astype(np.float32), axis=(0, 1))

    gu_drive_a = extract_pose(
        im_gu_r7,
        (24, 148, 332, 634),
        bg_gu7,
        pockets=[(0.36, 0.04, 0.62, 0.24), (0.25, 0.34, 0.55, 0.68), (0.35, 0.62, 0.72, 0.92)],
    )
    gu_drive_b = extract_pose(
        im_gu_r7,
        (338, 154, 638, 632),
        bg_gu7,
        pockets=[(0.36, 0.04, 0.62, 0.24), (0.22, 0.36, 0.54, 0.68), (0.36, 0.62, 0.78, 0.92)],
    )
    gu_seal = extract_pose(
        im_gu_r7,
        (1018, 182, 1352, 646),
        bg_gu7,
        pockets=[(0.30, 0.04, 0.56, 0.22), (0.25, 0.62, 0.85, 0.96)],
    )
    gu_thrust = extract_pose(
        im_tb_r7,
        (46, 198, 558, 658),
        bg_tb7,
        pockets=[(0.30, 0.04, 0.58, 0.22), (0.12, 0.62, 0.76, 0.96)],
    )
    gu_back_drive = extract_pose(im_tb_r7, (548, 130, 792, 662), bg_tb7, pockets=[(0.28, 0.66, 0.75, 0.96)])

    pei_slash = extract_pose(im_ps_r7, (356, 186, 774, 610), bg_ps7, pockets=[(0.18, 0.64, 0.72, 0.96)])
    shen_cast_r7 = extract_pose(
        im_ps_r7, (998, 152, 1352, 574), bg_ps7, pockets=[(0.04, 0.06, 0.46, 0.40), (0.06, 0.50, 0.36, 0.78)]
    )
    shen_stride_r7 = extract_pose(im_ps_r7, (744, 168, 988, 604), bg_ps7, pockets=[(0.05, 0.42, 0.42, 0.62)])
    shen_back_drive = extract_pose(im_tb_r7, (1058, 158, 1332, 664), bg_tb7, pockets=[(0.30, 0.74, 0.76, 0.97)])

    # R8 grounded walk & full-weapon combat master plates
    im_gu_r8 = np.asarray(Image.open(REPO_ROOT / "assets_src/sprites/r8_gu_walk_combat_raw.jpg").convert("RGB"))
    im_pei_r8 = np.asarray(Image.open(REPO_ROOT / "assets_src/sprites/r8_pei_walk_combat_raw.jpg").convert("RGB"))
    im_sh_r8 = np.asarray(Image.open(REPO_ROOT / "assets_src/sprites/r8_shen_walk_combat_raw.jpg").convert("RGB"))
    im_bk_r8 = np.asarray(Image.open(REPO_ROOT / "assets_src/sprites/r8_back_walk_raw.jpg").convert("RGB"))

    bg_gu8 = np.median(im_gu_r8[:20, :20, :].astype(np.float32), axis=(0, 1))
    bg_pei8 = np.median(im_pei_r8[:20, :20, :].astype(np.float32), axis=(0, 1))
    bg_sh8 = np.median(im_sh_r8[:20, :20, :].astype(np.float32), axis=(0, 1))
    bg_bk8 = np.median(im_bk_r8[:20, :20, :].astype(np.float32), axis=(0, 1))

    gu_walk_l = extract_pose(
        im_gu_r8, (68, 152, 284, 640), bg_gu8, pockets=[(0.12, 0.52, 0.44, 0.92), (0.35, 0.70, 0.80, 0.96)]
    )
    gu_walk_r = extract_pose(
        im_gu_r8, (582, 152, 796, 646), bg_gu8, pockets=[(0.12, 0.52, 0.44, 0.92), (0.35, 0.70, 0.80, 0.96)]
    )
    gu_chamber = extract_pose(
        im_gu_r8, (798, 174, 1052, 648), bg_gu8, pockets=[(0.22, 0.66, 0.82, 0.97), (0.28, 0.22, 0.56, 0.44)]
    )
    gu_cleave = extract_pose(
        im_gu_r8, (1048, 178, 1330, 646), bg_gu8, pockets=[(0.18, 0.64, 0.84, 0.97)]
    )

    pei_guard_se = extract_pose(
        im_pei_r8, (78, 170, 292, 620), bg_pei8, pockets=[(0.12, 0.50, 0.42, 0.92), (0.26, 0.74, 0.72, 0.97)]
    )
    pei_walk_l = extract_pose(
        im_pei_r8, (296, 170, 540, 620), bg_pei8, pockets=[(0.16, 0.52, 0.52, 0.94), (0.34, 0.68, 0.78, 0.96)]
    )
    pei_walk_m = extract_pose(
        im_pei_r8, (580, 172, 804, 616), bg_pei8, pockets=[(0.16, 0.52, 0.46, 0.92), (0.28, 0.72, 0.72, 0.96)]
    )
    pei_walk_r = extract_pose(
        im_pei_r8, (798, 170, 1056, 618), bg_pei8, pockets=[(0.16, 0.52, 0.52, 0.94), (0.34, 0.68, 0.78, 0.96)]
    )
    pei_high_windup = extract_pose(
        im_pei_r8, (1066, 164, 1356, 620), bg_pei8, pockets=[(0.22, 0.62, 0.82, 0.97), (0.24, 0.16, 0.58, 0.42)]
    )

    shen_walk_l = extract_pose(im_sh_r8, (52, 164, 254, 585), bg_sh8)
    shen_walk_m = extract_pose(im_sh_r8, (292, 164, 506, 589), bg_sh8)
    shen_walk_r = extract_pose(im_sh_r8, (536, 164, 756, 591), bg_sh8, pockets=[(0.04, 0.54, 0.34, 0.84)])
    shen_mudra = extract_pose(
        im_sh_r8, (786, 164, 1000, 588), bg_sh8, pockets=[(0.06, 0.34, 0.34, 0.84), (0.72, 0.50, 0.96, 0.88)]
    )
    shen_release = extract_pose(
        im_sh_r8,
        (1010, 164, 1344, 582),
        bg_sh8,
        pockets=[(0.04, 0.18, 0.44, 0.50), (0.04, 0.52, 0.38, 0.88), (0.64, 0.46, 0.92, 0.88)],
    )

    gu_back_l = extract_pose(
        im_bk_r8, (28, 166, 238, 624), bg_bk8, pockets=[(0.10, 0.52, 0.38, 0.86), (0.26, 0.72, 0.78, 0.96)]
    )
    gu_back_r = extract_pose(
        im_bk_r8, (242, 166, 450, 624), bg_bk8, pockets=[(0.10, 0.52, 0.38, 0.86), (0.26, 0.72, 0.78, 0.96)]
    )
    pei_back_l = extract_pose(
        im_bk_r8, (478, 154, 690, 626), bg_bk8, pockets=[(0.26, 0.72, 0.78, 0.96)]
    )
    pei_back_r = extract_pose(
        im_bk_r8, (686, 154, 926, 626), bg_bk8, pockets=[(0.08, 0.52, 0.38, 0.84), (0.28, 0.72, 0.78, 0.96)]
    )
    shen_back_l = extract_pose(im_bk_r8, (946, 184, 1132, 628), bg_bk8)
    shen_back_r = extract_pose(im_bk_r8, (1144, 184, 1330, 628), bg_bk8)

    updates: list[dict[str, str]] = []

    # ==================== HERO 1: GU CHANGQING (`target_h = 162`) ====================
    gu_th = 162
    gu_is, gu_is_y = r7_cave.scale_pose_to_height(gu_idle_se, gu_th)
    gu_in, gu_in_y = r7_cave.scale_pose_to_height(gu_idle_ne, gu_th)
    gu_wl, gu_wl_y = r7_cave.scale_pose_to_height(gu_walk_l, 160)
    gu_wr, gu_wr_y = r7_cave.scale_pose_to_height(gu_walk_r, 160)
    gu_da, gu_da_y = r7_cave.scale_pose_to_height(gu_drive_a, 157)
    gu_db, gu_db_y = r7_cave.scale_pose_to_height(gu_drive_b, 157)
    gu_bl, gu_bl_y = r7_cave.scale_pose_to_height(gu_back_l, 160)
    gu_br, gu_br_y = r7_cave.scale_pose_to_height(gu_back_r, 160)
    gu_bd, gu_bd_y = r7_cave.scale_pose_to_height(gu_back_drive, 158)
    gu_ch, gu_ch_y = r7_cave.scale_pose_to_height(gu_chamber, 154)
    gu_cv, gu_cv_y = r7_cave.scale_pose_to_height(gu_cleave, 154)
    gu_tr, gu_tr_y = r7_cave.scale_pose_to_height(gu_thrust, 150, max_w=246)
    gu_sl, gu_sl_y = r7_cave.scale_pose_to_height(gu_seal, 156)

    gu_sheet = np.zeros((ch * rows_cnt, cw * cols, 4), dtype=np.uint8)
    for f in range(4):
        gu_sheet[0:ch, f * cw : (f + 1) * cw] = r6_act.render_canonical_idle_cell(gu_is, gu_is_y, cw, ch, foot_y, f, 4)
        gu_sheet[ch : 2 * ch, f * cw : (f + 1) * cw] = r6_act.render_canonical_idle_cell(gu_in, gu_in_y, cw, ch, foot_y, f, 4)

    # Row 2 (`run_se`): 100% cohesive grounded brisk-stride cycle — ZERO `lower_tuck_px`, `scale_x = 1.0`, ZERO hair pop!
    gu_run_se_specs = [
        (gu_wl, gu_wl_y, -2.0, -2.8, 5.0),
        (gu_wl, gu_wl_y, 0.5, 0.8, -2.0),
        (gu_wr, gu_wr_y, 2.5, 3.4, -5.5),
        (gu_wr, gu_wr_y, 1.0, 1.2, -2.5),
        (gu_wl, gu_wl_y, -1.5, -3.2, 5.5),
        (gu_wr, gu_wr_y, 0.0, -0.5, 1.5),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p) in enumerate(gu_run_se_specs):
        gu_sheet[2 * ch : 3 * ch, f * cw : (f + 1) * cw] = r7_cave.place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p
        )

    # Row 3 (`run_ne`): 100% cohesive grounded 3/4 back brisk-stride cycle — ZERO `lower_tuck_px` & ZERO hair pop!
    gu_run_ne_specs = [
        (gu_bl, gu_bl_y, -1.5, -2.2, 4.0),
        (gu_bl, gu_bl_y, 0.5, 1.0, -2.0),
        (gu_br, gu_br_y, 2.0, 2.8, -4.5),
        (gu_br, gu_br_y, 0.5, 0.8, -1.5),
        (gu_bl, gu_bl_y, -1.0, -2.5, 4.5),
        (gu_br, gu_br_y, 0.0, -0.5, 1.0),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p) in enumerate(gu_run_ne_specs):
        gu_sheet[3 * ch : 4 * ch, f * cw : (f + 1) * cw] = r7_cave.place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p
        )

    # Row 4 (`attack_1`): True 4-pose progression (Uncut Chamber -> Deep Thrust -> Wide Low Cleave -> Guard -> Seal)
    gu_atk1_specs = [
        (gu_ch, gu_ch_y, -5.0, -1.5, 1.5),
        (gu_tr, gu_tr_y, 9.0, 0.5, -3.0),
        (gu_tr, gu_tr_y, 15.0, 2.2, -4.5),
        (gu_cv, gu_cv_y, 8.0, 2.0, -2.0),
        (gu_sl, gu_sl_y, 2.0, 0.5, 0.0),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p) in enumerate(gu_atk1_specs):
        gu_sheet[4 * ch : 5 * ch, f * cw : (f + 1) * cw] = r7_cave.place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p
        )

    # Row 5 (`attack_2`): Seal -> Uncut Chamber -> Wide Cleave -> Deep Thrust -> Grounded Sword Recovery
    gu_atk2_specs = [
        (gu_sl, gu_sl_y, -3.0, -1.5, 1.5),
        (gu_ch, gu_ch_y, -5.0, -2.0, 2.0),
        (gu_cv, gu_cv_y, 8.0, 1.5, -2.5),
        (gu_tr, gu_tr_y, 13.0, 2.5, -4.0),
        (gu_wl, gu_wl_y, 2.0, 0.0, 0.0),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p) in enumerate(gu_atk2_specs):
        gu_sheet[5 * ch : 6 * ch, f * cw : (f + 1) * cw] = r7_cave.place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p
        )

    # Row 6 (`cast_loop` 0..2 + `cast_release` 3..5)
    gu_cast_specs = [
        (gu_sl, gu_sl_y, 0.0, 0.0, -2.0),
        (gu_sl, gu_sl_y, 0.0, -1.0, 2.5),
        (gu_ch, gu_ch_y, -2.0, 0.0, -1.5),
        (gu_tr, gu_tr_y, 12.0, 0.5, -3.5),
        (gu_cv, gu_cv_y, 7.0, 1.5, -2.0),
        (gu_sl, gu_sl_y, 1.5, 0.0, 0.0),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p) in enumerate(gu_cast_specs):
        gu_sheet[6 * ch : 7 * ch, f * cw : (f + 1) * cw] = r7_cave.place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p
        )

    # Row 7 (`hit` 0..1 + `down` 2..3)
    gu_sheet[7 * ch : 8 * ch, 0:cw] = r7_cave.place_pose_on_cell(
        gu_ch, gu_ch_y, cw, ch, foot_y, dx_px=-8.0, rot_deg=-5.5, hem_sway_px=3.5, tint_rgb=(1.13, 0.92, 0.90)
    )
    gu_sheet[7 * ch : 8 * ch, cw : 2 * cw] = r7_cave.place_pose_on_cell(
        gu_sl, gu_sl_y, cw, ch, foot_y, dx_px=-4.0, rot_deg=-3.0, hem_sway_px=2.0, tint_rgb=(1.05, 0.96, 0.95)
    )
    gu_sheet[7 * ch : 8 * ch, 2 * cw : 3 * cw] = r7_cave.make_fallen_pose_cell(gu_idle_se, gu_th, cw, ch, foot_y, 74.0)
    gu_sheet[7 * ch : 8 * ch, 3 * cw : 4 * cw] = r7_cave.make_fallen_pose_cell(gu_idle_se, gu_th, cw, ch, foot_y, 82.0)

    # ==================== HERO 2: PEI ZHAO (`target_h = 166`, 100% BRONZE BROADSWORD!) ====================
    pei_th = 166
    pei_is, pei_is_y = r7_cave.scale_pose_to_height(pei_guard_se, pei_th)
    pei_in, pei_in_y = r7_cave.scale_pose_to_height(pei_idle_ne, pei_th)
    pei_wl, pei_wl_y = r7_cave.scale_pose_to_height(pei_walk_l, 164)
    pei_wm, pei_wm_y = r7_cave.scale_pose_to_height(pei_walk_m, 164)
    pei_wr, pei_wr_y = r7_cave.scale_pose_to_height(pei_walk_r, 164)
    pei_bl, pei_bl_y = r7_cave.scale_pose_to_height(pei_back_l, 164)
    pei_br, pei_br_y = r7_cave.scale_pose_to_height(pei_back_r, 164)
    pei_hw, pei_hw_y = r7_cave.scale_pose_to_height(pei_high_windup, 160, max_w=236)
    pei_sl, pei_sl_y = r7_cave.scale_pose_to_height(pei_slash, 154, max_w=246)

    pei_sheet = np.zeros((ch * rows_cnt, cw * cols, 4), dtype=np.uint8)
    for f in range(4):
        pei_sheet[0:ch, f * cw : (f + 1) * cw] = r6_act.render_canonical_idle_cell(pei_is, pei_is_y, cw, ch, foot_y, f, 4)
        pei_sheet[ch : 2 * ch, f * cw : (f + 1) * cw] = r6_act.render_canonical_idle_cell(pei_in, pei_in_y, cw, ch, foot_y, f, 4)

    # Row 2 (`run_se`): Grounded bronze-broadsword walk cycle — ZERO `lower_tuck_px` & ZERO bare hands!
    pei_run_se_specs = [
        (pei_wl, pei_wl_y, 0.0, 2.5, -5.0),
        (pei_wm, pei_wm_y, 1.0, -2.5, 4.5),
        (pei_wr, pei_wr_y, 2.0, 3.5, -6.0),
        (pei_wr, pei_wr_y, 0.5, -1.5, 3.0),
        (pei_wm, pei_wm_y, 0.5, -3.0, 5.0),
        (pei_wl, pei_wl_y, 0.0, 0.5, -1.5),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p) in enumerate(pei_run_se_specs):
        pei_sheet[2 * ch : 3 * ch, f * cw : (f + 1) * cw] = r7_cave.place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p
        )

    # Row 3 (`run_ne`): Grounded 3/4 back bronze-broadsword walk cycle
    pei_run_ne_specs = [
        (pei_bl, pei_bl_y, 0.0, 0.0, 0.0),
        (pei_bl, pei_bl_y, 0.5, 1.5, -3.5),
        (pei_br, pei_br_y, 0.5, 1.0, -2.0),
        (pei_br, pei_br_y, 0.0, -1.5, 3.0),
        (pei_br, pei_br_y, -0.5, 0.5, -1.5),
        (pei_bl, pei_bl_y, 0.0, -1.0, 2.0),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p) in enumerate(pei_run_ne_specs):
        pei_sheet[3 * ch : 4 * ch, f * cw : (f + 1) * cw] = r7_cave.place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p
        )

    # Row 4 (`attack_1`): High Overhead Windup -> Sweeping Greatsword Cleave -> Peak Lunge -> Low Follow -> Bronze Guard
    pei_atk1_specs = [
        (pei_hw, pei_hw_y, -5.0, -2.0, 2.0),
        (pei_sl, pei_sl_y, 8.0, -1.5, -2.5),
        (pei_sl, pei_sl_y, 14.0, 2.5, -4.5),
        (pei_wm, pei_wm_y, 7.0, 4.0, -2.0),
        (pei_is, pei_is_y, 2.0, 0.5, 0.0),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p) in enumerate(pei_atk1_specs):
        pei_sheet[4 * ch : 5 * ch, f * cw : (f + 1) * cw] = r7_cave.place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p
        )

    # Row 5 (`attack_2`): Guard -> Step Chamber -> Overhead Windup -> Heavy Cleave -> Recovery
    pei_atk2_specs = [
        (pei_is, pei_is_y, -3.0, -2.0, 1.5),
        (pei_hw, pei_hw_y, -4.0, -1.0, 2.0),
        (pei_sl, pei_sl_y, 13.0, 3.5, -4.5),
        (pei_sl, pei_sl_y, 8.0, 5.0, -2.5),
        (pei_wm, pei_wm_y, 2.0, 1.0, 0.0),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p) in enumerate(pei_atk2_specs):
        pei_sheet[5 * ch : 6 * ch, f * cw : (f + 1) * cw] = r7_cave.place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p
        )

    # Row 6 (`cast_loop` 0..2 + `cast_release` 3..5)
    pei_cast_specs = [
        (pei_hw, pei_hw_y, 0.0, 0.0, -1.5),
        (pei_hw, pei_hw_y, 0.0, -1.5, 2.0),
        (pei_hw, pei_hw_y, 0.0, 0.5, -2.5),
        (pei_sl, pei_sl_y, 12.0, 2.0, -4.0),
        (pei_wm, pei_wm_y, 6.0, 2.5, -1.5),
        (pei_is, pei_is_y, 1.5, 0.0, 0.0),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p) in enumerate(pei_cast_specs):
        pei_sheet[6 * ch : 7 * ch, f * cw : (f + 1) * cw] = r7_cave.place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p
        )

    # Row 7 (`hit` 0..1 + `down` 2..3 — holding bronze broadsword!)
    pei_sheet[7 * ch : 8 * ch, 0:cw] = r7_cave.place_pose_on_cell(
        pei_hw, pei_hw_y, cw, ch, foot_y, dx_px=-8.0, rot_deg=-5.5, hem_sway_px=3.5, tint_rgb=(1.13, 0.92, 0.90)
    )
    pei_sheet[7 * ch : 8 * ch, cw : 2 * cw] = r7_cave.place_pose_on_cell(
        pei_is, pei_is_y, cw, ch, foot_y, dx_px=-4.0, rot_deg=-3.0, hem_sway_px=2.0, tint_rgb=(1.05, 0.96, 0.95)
    )
    pei_sheet[7 * ch : 8 * ch, 2 * cw : 3 * cw] = r7_cave.make_fallen_pose_cell(pei_guard_se, pei_th, cw, ch, foot_y, 74.0)
    pei_sheet[7 * ch : 8 * ch, 3 * cw : 4 * cw] = r7_cave.make_fallen_pose_cell(pei_guard_se, pei_th, cw, ch, foot_y, 82.0)

    # ==================== HERO 3: SHEN QINGHE (`target_h = 152`, ZERO NEEDLE-CONE SKIRT!) ====================
    shen_th = 152
    sh_is, sh_is_y = r7_cave.scale_pose_to_height(shen_idle_se, shen_th)
    sh_in, sh_in_y = r7_cave.scale_pose_to_height(shen_idle_ne, shen_th)
    sh_wl, sh_wl_y = r7_cave.scale_pose_to_height(shen_walk_l, 151)
    sh_wm, sh_wm_y = r7_cave.scale_pose_to_height(shen_walk_m, 151)
    sh_wr, sh_wr_y = r7_cave.scale_pose_to_height(shen_walk_r, 151)
    sh_bl, sh_bl_y = r7_cave.scale_pose_to_height(shen_back_l, 151)
    sh_br, sh_br_y = r7_cave.scale_pose_to_height(shen_back_r, 151)
    sh_md, sh_md_y = r7_cave.scale_pose_to_height(shen_mudra, 152)
    sh_c7, sh_c7_y = r7_cave.scale_pose_to_height(shen_cast_r7, 152, max_w=228)
    sh_rl, sh_rl_y = r7_cave.scale_pose_to_height(shen_release, 152, max_w=242)

    shen_sheet = np.zeros((ch * rows_cnt, cw * cols, 4), dtype=np.uint8)
    for f in range(4):
        shen_sheet[0:ch, f * cw : (f + 1) * cw] = r6_act.render_canonical_idle_cell(sh_is, sh_is_y, cw, ch, foot_y, f, 4)
        shen_sheet[ch : 2 * ch, f * cw : (f + 1) * cw] = r6_act.render_canonical_idle_cell(sh_in, sh_in_y, cw, ch, foot_y, f, 4)

    # Row 2 (`run_se`): 100% cohesive cream-and-celadon full-skirt grounded walk — ZERO `lower_tuck_px` & ZERO jacket pop!
    shen_run_se_specs = [
        (sh_wl, sh_wl_y, -2.5, -3.2, 5.5),
        (sh_wm, sh_wm_y, 0.5, 1.2, -3.0),
        (sh_wr, sh_wr_y, 3.0, 3.8, -6.5),
        (sh_wr, sh_wr_y, 1.0, 1.0, -2.0),
        (sh_wm, sh_wm_y, -1.5, -2.8, 5.0),
        (sh_wl, sh_wl_y, -0.5, -0.8, 2.0),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p) in enumerate(shen_run_se_specs):
        shen_sheet[2 * ch : 3 * ch, f * cw : (f + 1) * cw] = r7_cave.place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p
        )

    # Row 3 (`run_ne`): 100% cohesive 3/4 back grounded walk cycle — ZERO `lower_tuck_px` & ZERO loose-hair pop!
    shen_run_ne_specs = [
        (sh_bl, sh_bl_y, -1.5, -2.2, 4.0),
        (sh_bl, sh_bl_y, 0.5, 1.0, -2.0),
        (sh_br, sh_br_y, 2.0, 2.6, -4.5),
        (sh_br, sh_br_y, 0.5, 0.8, -1.5),
        (sh_bl, sh_bl_y, -1.0, -2.4, 4.0),
        (sh_br, sh_br_y, 0.0, -0.5, 1.0),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p) in enumerate(shen_run_ne_specs):
        shen_sheet[3 * ch : 4 * ch, f * cw : (f + 1) * cw] = r7_cave.place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p
        )

    # Row 4 (`attack_1`): 100% cream-and-celadon Lotus Mudra Gather -> Twin-Sleeve Lead -> Peak Release -> Follow -> Mudra
    shen_atk1_specs = [
        (sh_md, sh_md_y, -3.0, -1.5, 1.5),
        (sh_rl, sh_rl_y, 7.0, 2.0, -3.5),
        (sh_rl, sh_rl_y, 13.0, 5.5, -7.0),
        (sh_rl, sh_rl_y, 8.0, 3.0, -3.0),
        (sh_md, sh_md_y, 1.5, 0.0, 0.0),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p) in enumerate(shen_atk1_specs):
        shen_sheet[4 * ch : 5 * ch, f * cw : (f + 1) * cw] = r7_cave.place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p
        )

    # Row 5 (`attack_2`): Flowing Walk-Step -> Mudra -> Twin-Sleeve Release -> Follow -> Graceful Recovery (ZERO stiff idle!)
    shen_atk2_specs = [
        (sh_wr, sh_wr_y, -3.0, -1.5, 1.5),
        (sh_md, sh_md_y, -2.0, -1.0, 2.0),
        (sh_rl, sh_rl_y, 12.0, 4.5, -6.0),
        (sh_rl, sh_rl_y, 7.5, 3.0, -3.0),
        (sh_wm, sh_wm_y, 1.5, 0.5, 0.0),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p) in enumerate(shen_atk2_specs):
        shen_sheet[5 * ch : 6 * ch, f * cw : (f + 1) * cw] = r7_cave.place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p
        )

    # Row 6 (`cast_loop` 0..2 + `cast_release` 3..5)
    shen_cast_specs = [
        (sh_md, sh_md_y, 0.0, 0.0, -2.0),
        (sh_md, sh_md_y, 0.0, -1.0, 2.5),
        (sh_c7, sh_c7_y, 2.0, -0.5, -2.0),
        (sh_rl, sh_rl_y, 10.0, 2.5, -4.5),
        (sh_c7, sh_c7_y, 5.0, 2.0, -2.0),
        (sh_md, sh_md_y, 1.0, 0.0, 0.0),
    ]
    for f, (im_p, sy_p, dx_p, rot_p, sw_p) in enumerate(shen_cast_specs):
        shen_sheet[6 * ch : 7 * ch, f * cw : (f + 1) * cw] = r7_cave.place_pose_on_cell(
            im_p, sy_p, cw, ch, foot_y, dx_px=dx_p, rot_deg=rot_p, hem_sway_px=sw_p
        )

    # Row 7 (`hit` 0..1 + `down` 2..3)
    shen_sheet[7 * ch : 8 * ch, 0:cw] = r7_cave.place_pose_on_cell(
        sh_md, sh_md_y, cw, ch, foot_y, dx_px=-7.0, rot_deg=-5.0, hem_sway_px=3.5, tint_rgb=(1.13, 0.92, 0.90)
    )
    shen_sheet[7 * ch : 8 * ch, cw : 2 * cw] = r7_cave.place_pose_on_cell(
        sh_wm, sh_wm_y, cw, ch, foot_y, dx_px=-3.5, rot_deg=-2.5, hem_sway_px=2.0, tint_rgb=(1.05, 0.96, 0.95)
    )
    shen_sheet[7 * ch : 8 * ch, 2 * cw : 3 * cw] = r7_cave.make_fallen_pose_cell(shen_idle_se, shen_th, cw, ch, foot_y, 74.0)
    shen_sheet[7 * ch : 8 * ch, 3 * cw : 4 * cw] = r7_cave.make_fallen_pose_cell(shen_idle_se, shen_th, cw, ch, foot_y, 82.0)

    hero_bundles = [
        ("gu_changqing", gu_sheet, "assets_src/sprites/r8_gu_walk_combat_raw.jpg", 8.5),
        ("pei_zhao", pei_sheet, "assets_src/sprites/r8_pei_walk_combat_raw.jpg", 8.5),
        ("shen_qinghe", shen_sheet, "assets_src/sprites/r8_shen_walk_combat_raw.jpg", 8.5),
    ]
    for aid, sheet_arr, src_rel, run_fps in hero_bundles:
        sheet_clean = r6_act.clamp_song_ming_mineral_hsv(sheet_arr)
        assert count_fluorescent_pixels(sheet_clean) == 0, f"Fluorescent pixels in {aid}_sheet.png"

        rel_png = f"project/assets/sprites/{aid}_sheet.png"
        rel_json = f"project/assets/sprites/{aid}_sheet.json"
        abs_png = REPO_ROOT / rel_png
        abs_json = REPO_ROOT / rel_json
        Image.fromarray(sheet_clean, mode="RGBA").save(abs_png, format="PNG", optimize=False)

        meta = json.loads(abs_json.read_text(encoding="utf-8"))
        idle_cell = sheet_clean[0:ch, 0:cw]
        ys_i, xs_i = np.where(idle_cell[..., 3] >= 16)
        meta["head_top_px"] = int(max(68, foot_y - int(ys_i.min())))
        meta["rows"]["run_se"]["fps"] = run_fps
        meta["rows"]["run_ne"]["fps"] = run_fps
        abs_json.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

        rep = analyze_sprite_sheet_cells(abs_png, abs_json, alpha_thresh=16)
        rows_rep = rep["rows"]
        idle_w = int(rows_rep["idle_se"]["max_w"])
        idle_h = int(rows_rep["idle_se"]["max_h"])
        atk_w = max(int(rows_rep["attack_1"]["max_w"]), int(rows_rep["attack_2"]["max_w"]))
        down_h = int(rows_rep["down"]["max_h"])
        ext_ratio = atk_w / max(1.0, float(idle_w))
        down_ratio = down_h / max(1.0, float(idle_h))
        run_iou = float(rows_rep["run_se"]["intra_row_min_iou"])
        idle_atk_iou = float(rep["pairwise_row_iou"]["idle_se:attack_1"])
        idle_cast_iou = float(rep["pairwise_row_iou"]["idle_se:cast_loop"])
        tot_border = int(rep["total_border_opaque_px"])
        print(
            f"  [R8 hero {aid}] idle={idle_w}x{idle_h}, atk_ext={ext_ratio:.2f}x, down={down_ratio:.2f}x, "
            f"run_iou={run_iou:.3f}, idle_atk_iou={idle_atk_iou:.3f}, idle_cast_iou={idle_cast_iou:.3f}, border={tot_border}"
        )
        assert ext_ratio >= 1.32, f"{aid} ext_ratio={ext_ratio:.3f} < 1.32"
        assert down_ratio <= 0.75, f"{aid} down_ratio={down_ratio:.3f} > 0.75"
        assert run_iou <= 0.66, f"{aid} run_iou={run_iou:.3f} > 0.66"
        assert idle_atk_iou <= 0.55, f"{aid} idle_atk_iou={idle_atk_iou:.3f} > 0.55"
        assert idle_cast_iou <= 0.70, f"{aid} idle_cast_iou={idle_cast_iou:.3f} > 0.70"
        assert tot_border == 0, f"{aid} border opaque px={tot_border}"

        updates.append(
            {
                "path": rel_png,
                "source_path": src_rel,
                "category": "sprite_sheet",
                "creation_method": (
                    f"Gemini Imagen (2026-11-28, Song-Ming Gongbi grounded walk & unified-weapon combat plates {src_rel}, "
                    f"r8_back_walk_raw.jpg, r7_*_multipose_raw.jpg & char_ref_party_*_raw.jpg) + "
                    f"tools/build_polish_r8_gait_town_and_hud.py zero-pinch natural stride & multi-pose combo assembly ({aid})"
                ),
                "license": LIC_R8,
            }
        )
    return updates


def build_r8_multipose_enemies_and_fox() -> list[dict[str, str]]:
    """
    Injects genuine second hand-painted Song-Ming Gongbi lunge/stride keyframes from `r8_enemies_fox_multipose_raw.jpg`
    into `enemy_rot_wolf`, `enemy_wood_golem`, `enemy_miasma_shaman`, `enemy_rogue_cultivator`, and `pet_fire_fox`
    so enemies & the spirit fox run and lunge with real alternating limbs instead of pure mesh shear!
    """
    src_rel = "assets_src/sprites/r8_enemies_fox_multipose_raw.jpg"
    im_ef = np.asarray(Image.open(REPO_ROOT / src_rel).convert("RGB"))
    bg_ef = np.median(im_ef[:20, :20, :].astype(np.float32), axis=(0, 1))

    pose_specs = [
        ("enemy_rot_wolf", (18, 134, 442, 362), 116, 212),
        ("enemy_wood_golem", (538, 64, 918, 390), 178, 224),
        ("enemy_miasma_shaman", (976, 86, 1348, 378), 156, 216),
        ("enemy_rogue_cultivator", (238, 414, 646, 692), 154, 232),
        ("pet_fire_fox", (740, 448, 1140, 694), 96, 178),
    ]

    updates: list[dict[str, str]] = []
    for aid, crop_box, target_h, max_w in pose_specs:
        rel_png = f"project/assets/sprites/{aid}_sheet.png"
        rel_json = f"project/assets/sprites/{aid}_sheet.json"
        abs_png = REPO_ROOT / rel_png
        abs_json = REPO_ROOT / rel_json

        sheet = np.asarray(Image.open(abs_png).convert("RGBA")).copy()
        meta = json.loads(abs_json.read_text(encoding="utf-8"))
        cw = int(meta["cell_w"])
        ch = int(meta["cell_h"])
        fy = int(meta["foot_y"])

        alt_cut = extract_pose(im_ef, crop_box, bg_ef, tol=22.0)
        alt_sc, alt_sy = r7_cave.scale_pose_to_height(alt_cut, target_h, max_w=min(max_w, cw - 16))

        # Splice real alternating hand-painted stride frames into Row 2 (`run_se`, cols 1, 2, 4)
        sheet[2 * ch : 3 * ch, 1 * cw : 2 * cw] = r7_cave.place_pose_on_cell(
            alt_sc, alt_sy, cw, ch, fy, dx_px=2.0, rot_deg=-1.0
        )
        sheet[2 * ch : 3 * ch, 2 * cw : 3 * cw] = r7_cave.place_pose_on_cell(
            alt_sc, alt_sy, cw, ch, fy, dx_px=4.0, rot_deg=1.5
        )
        sheet[2 * ch : 3 * ch, 4 * cw : 5 * cw] = r7_cave.place_pose_on_cell(
            alt_sc, alt_sy, cw, ch, fy, dx_px=1.0, rot_deg=-1.5
        )

        # Splice real hand-painted lunge/attack poses into Rows 4 & 5 (`attack_1`, `attack_2` cols 1, 2, 3)
        for r_atk, rot_add in ((4, 0.0), (5, 1.5)):
            sheet[r_atk * ch : (r_atk + 1) * ch, 1 * cw : 2 * cw] = r7_cave.place_pose_on_cell(
                alt_sc, alt_sy, cw, ch, fy, dx_px=5.0, rot_deg=-1.5 + rot_add
            )
            sheet[r_atk * ch : (r_atk + 1) * ch, 2 * cw : 3 * cw] = r7_cave.place_pose_on_cell(
                alt_sc, alt_sy, cw, ch, fy, dx_px=10.0, rot_deg=2.0 + rot_add
            )
            sheet[r_atk * ch : (r_atk + 1) * ch, 3 * cw : 4 * cw] = r7_cave.place_pose_on_cell(
                alt_sc, alt_sy, cw, ch, fy, dx_px=6.0, rot_deg=3.0 + rot_add
            )

        sheet_clean = r6_act.clamp_song_ming_mineral_hsv(sheet)
        assert count_fluorescent_pixels(sheet_clean) == 0, f"Fluorescent px in {aid}"
        Image.fromarray(sheet_clean, mode="RGBA").save(abs_png, format="PNG", optimize=False)

        rep = analyze_sprite_sheet_cells(abs_png, abs_json, alpha_thresh=16)
        tot_border = int(rep["total_border_opaque_px"])
        assert tot_border == 0, f"{aid} border bleed={tot_border}"

        updates.append(
            {
                "path": rel_png,
                "source_path": src_rel,
                "category": "sprite_sheet",
                "creation_method": (
                    f"Gemini Imagen (2026-11-28, Song-Ming Gongbi creature/enemy multi-pose action sheet {src_rel}) + "
                    f"tools/build_polish_r8_gait_town_and_hud.py genuine 2-pose stride & lunge splice ({aid})"
                ),
                "license": LIC_R8,
            }
        )
    return updates


def build_r8_town_and_hud_assets() -> list[dict[str, str]]:
    updates: list[dict[str, str]] = []

    # 1. Rich painterly 2x2 human-scale Jiangnan mossy earth, pebbles & ink grass turf (`tex_moss_earth.png`)
    meadow_src = "assets_src/world/r8_town_moss_meadow_raw.jpg"
    raw_meadow = np.asarray(Image.open(REPO_ROOT / meadow_src).convert("RGB"))
    toned_meadow = np.clip(
        raw_meadow.astype(np.float32) * np.array([0.82, 0.88, 0.84], dtype=np.float32), 0, 255
    ).astype(np.uint8)
    m_cell = r7_cave.make_seamless_cosine_tile(toned_meadow, out_size=512, overlap=80)
    m_2x2 = np.tile(m_cell, (2, 2, 1)).astype(np.float32)
    yy_m, xx_m = np.meshgrid(np.arange(1024, dtype=np.float32), np.arange(1024, dtype=np.float32), indexing="ij")
    mod_m = 1.0 + 0.04 * np.sin(2.0 * math.pi * xx_m / 1024.0) * np.cos(2.0 * math.pi * yy_m / 1024.0)
    m_2x2[..., :3] = np.clip(m_2x2[..., :3] * mod_m[..., None], 0, 255)
    meadow_tile = r6_act.clamp_song_ming_mineral_hsv(m_2x2.astype(np.uint8))
    assert count_fluorescent_pixels(meadow_tile) == 0
    meadow_rel = "project/assets/world/tex_moss_earth.png"
    Image.fromarray(meadow_tile[..., :3], mode="RGB").save(REPO_ROOT / meadow_rel, format="PNG", optimize=False)
    updates.append(
        {
            "path": meadow_rel,
            "source_path": meadow_src,
            "category": "world_tile",
            "creation_method": (
                "Gemini Imagen (2026-11-28, prompt: 'Top-down 35-degree isometric uniform flat seamless ground texture "
                "in Song-Ming Gongbi style: damp rainy Jiangnan mossy earth with river pebbles and ink grass tufts') + "
                "tools/build_polish_r8_gait_town_and_hud.py 2x2 cosine-wrapped seamless tile"
            ),
            "license": LIC_R8,
        }
    )

    def keep_main_alpha_components(im_rgba: Image.Image, min_ratio: float = 0.08) -> Image.Image:
        arr = np.asarray(im_rgba.convert("RGBA")).copy()
        mask = (arr[..., 3] > 8).astype(np.uint8)
        num, lbl, stats, _ = cv2.connectedComponentsWithStats(mask)
        if num <= 1:
            return Image.fromarray(arr, mode="RGBA")
        max_area = int(stats[1:, cv2.CC_STAT_AREA].max())
        keep = np.zeros_like(mask, dtype=bool)
        for i in range(1, num):
            if int(stats[i, cv2.CC_STAT_AREA]) >= max(32, int(max_area * min_ratio)):
                keep |= lbl == i
        arr[~keep, 3] = 0
        ys, xs = np.where(arr[..., 3] > 8)
        if ys.size > 0:
            arr = arr[int(ys.min()) : int(ys.max()) + 1, int(xs.min()) : int(xs.max()) + 1]
        return Image.fromarray(arr, mode="RGBA")

    # 2. Four Jiangnan town & pharmacy courtyard props (`r8_town_courtyard_props_raw.jpg`)
    props_src = "assets_src/world/r8_town_courtyard_props_raw.jpg"
    im_pr = np.asarray(Image.open(REPO_ROOT / props_src).convert("RGB"))
    bg_pr = np.median(im_pr[:20, :20, :].astype(np.float32), axis=(0, 1))

    # (a) `prop_folk_house_c.png`: Timber-and-whitewash Jiangnan cottage with wooden lattice porch & celadon rainwater jar
    house_c_cut = keep_main_alpha_components(
        r5_town.extract_exterior_cutout(im_pr[18:608, 42:608], bg_pr, tol=21.0), min_ratio=0.12
    )
    house_c_rel = "project/assets/world/prop_folk_house_c.png"
    r5_town.save_grounded_rgba(house_c_cut, 384, 396, house_c_rel, shadow_alpha=78, pad_bot=4, lut_sat=0.92)
    updates.append(
        {
            "path": house_c_rel,
            "source_path": props_src,
            "category": "world_prop",
            "creation_method": (
                "Gemini Imagen (2026-11-28, Song-Ming Gongbi 35-degree Jiangnan timber-and-whitewash cottage with "
                "wooden lattice doors and celadon rainwater jar) + tools/build_polish_r8_gait_town_and_hud.py cutout"
            ),
            "license": LIC_R8,
        }
    )

    # (b) `prop_yaolu_drying_rack.png`: Bamboo herb-drying rack + celadon medicine jars + stone mortar
    rack_cut = r5_town.extract_exterior_cutout(
        im_pr[44:388, 768:1256], bg_pr, tol=21.0, extra_hole_boxes=[(10, 10, 300, 336)]
    )
    rack_rel = "project/assets/world/prop_yaolu_drying_rack.png"
    r5_town.save_grounded_rgba(rack_cut, 268, 206, rack_rel, shadow_alpha=68, pad_bot=4, lut_sat=0.92)
    updates.append(
        {
            "path": rack_rel,
            "source_path": props_src,
            "category": "world_prop",
            "creation_method": (
                "Gemini Imagen (2026-11-28, Song-Ming Gongbi 35-degree bamboo herb-drying rack, celadon medicine jars "
                "and stone mortar) + tools/build_polish_r8_gait_town_and_hud.py cutout"
            ),
            "license": LIC_R8,
        }
    )

    # (c) `prop_town_fence_vignette.png`: Woven-bamboo garden fence, mossy stone lantern, rainwater vat & ferns
    fence_cut = keep_main_alpha_components(
        r5_town.extract_exterior_cutout(im_pr[402:742, 520:882], bg_pr, tol=21.0), min_ratio=0.15
    )
    fence_rel = "project/assets/world/prop_town_fence_vignette.png"
    r5_town.save_grounded_rgba(fence_cut, 248, 232, fence_rel, shadow_alpha=72, pad_bot=4, lut_sat=0.92)
    updates.append(
        {
            "path": fence_rel,
            "source_path": props_src,
            "category": "world_prop",
            "creation_method": (
                "Gemini Imagen (2026-11-28, Song-Ming Gongbi 35-degree woven-bamboo courtyard fence with mossy stone "
                "lantern, clay rainwater vat and ferns) + tools/build_polish_r8_gait_town_and_hud.py cutout"
            ),
            "license": LIC_R8,
        }
    )

    # (d) `prop_town_garden_patch.png`: Mossy irregular flagstone garden patch with boxwood shrubs & wild irises
    garden_cut = r5_town.extract_exterior_cutout(im_pr[384:714, 886:1348], bg_pr, tol=22.0)
    garden_rel = "project/assets/world/prop_town_garden_patch.png"
    r5_town.save_grounded_rgba(garden_cut, 316, 228, garden_rel, shadow_alpha=54, pad_bot=4, lut_sat=0.92)
    updates.append(
        {
            "path": garden_rel,
            "source_path": props_src,
            "category": "world_prop",
            "creation_method": (
                "Gemini Imagen (2026-11-28, Song-Ming Gongbi 35-degree mossy flagstone garden patch with boxwood shrubs "
                "and wild iris leaves) + tools/build_polish_r8_gait_town_and_hud.py cutout"
            ),
            "license": LIC_R8,
        }
    )

    # (e) `prop_yaolu_wall_mid.png`: Seamless intermediate 35-deg whitewashed wall span (trims right gable horn &
    #     feathers right overlap strip so chained courtyard walls join with ZERO vertical black seam lines!)
    wall_cap = np.asarray(Image.open(REPO_ROOT / "project/assets/world/prop_yaolu_courtyard_wall.png").convert("RGBA")).copy()
    wall_mid = wall_cap.copy()
    h_wm, w_wm, _ = wall_mid.shape
    for x_col in range(106, w_wm):
        fade = max(0.0, 1.0 - float(x_col - 106) / 14.0)
        wall_mid[:, x_col, 3] = np.round(wall_mid[:, x_col, 3].astype(np.float32) * fade).astype(np.uint8)
    wall_mid[:, 121:, 3] = 0
    wall_mid_rel = "project/assets/world/prop_yaolu_wall_mid.png"
    Image.fromarray(wall_mid, mode="RGBA").save(REPO_ROOT / wall_mid_rel, format="PNG", optimize=False)
    updates.append(
        {
            "path": wall_mid_rel,
            "source_path": "assets_src/world/r5_yaolu_walls_lanterns_raw.jpg",
            "category": "world_prop",
            "creation_method": (
                "Gemini Imagen (assets_src/world/r5_yaolu_walls_lanterns_raw.jpg) + "
                "tools/build_polish_r8_gait_town_and_hud.py seamless intermediate courtyard wall feathering"
            ),
            "license": LIC_R8,
        }
    )

    # 3. Unified Warm Xuan-Parchment `96x96` HUD Skill & Item Icons (8 icons across ALL 3 playable characters!)
    icons_src = "assets_src/ui/r8_hud_xuan_icons_raw.jpg"
    icons_extra_src = "assets_src/ui/r8_hud_xuan_icons_extra_raw.jpg"
    im_ic = np.asarray(Image.open(REPO_ROOT / icons_src).convert("RGB"))
    im_ic_ex = np.asarray(Image.open(REPO_ROOT / icons_extra_src).convert("RGB"))

    def frame_xuan_icon_96(square_rgb: np.ndarray) -> np.ndarray:
        pil_sq = Image.fromarray(square_rgb, mode="RGB").resize((96, 96), Image.Resampling.LANCZOS)
        rgba = pil_sq.convert("RGBA")
        dr = ImageDraw.Draw(rgba)
        # Matching chamfered dark-ink + antique bronze-gold inner rim (identical grammar across all 10 HUD slots!)
        dr.rectangle([0, 0, 95, 95], outline=(24, 20, 17, 255), width=2)
        dr.rectangle([2, 2, 93, 93], outline=(188, 152, 92, 255), width=2)
        dr.rectangle([4, 4, 91, 91], outline=(92, 72, 44, 180), width=1)
        out_arr = r6_act.clamp_song_ming_mineral_hsv(np.asarray(rgba, dtype=np.uint8))
        assert count_fluorescent_pixels(out_arr) == 0
        return out_arr

    icon_jobs = [
        (im_ic, icons_src, "project/assets/ui/icons/sk_interrupt_seal.png", (55, 246, 325, 522), "Q interrupt bronze sword slicing spell circle"),
        (im_ic, icons_src, "project/assets/ui/icons/sk_lotus_shield.png", (387, 246, 657, 522), "E celadon-jade lotus shield talisman"),
        (im_ic, icons_src, "project/assets/ui/icons/sk_bond_qinglian.png", (719, 246, 989, 522), "R ebony-and-gold sword casket bursting with flying jade swords"),
        (im_ic, icons_src, "project/assets/ui/icons/hud_formation_bagua.png", (1051, 246, 1321, 522), "Z bronze-and-cinnabar Bagua compass"),
        (im_ic_ex, icons_extra_src, "project/assets/ui/icons/sk_metal_sword.png", (52, 248, 328, 524), "1 silver-celadon jian slashing pale-jade wind-qi arc"),
        (im_ic_ex, icons_extra_src, "project/assets/ui/icons/sk_earth_cleave.png", (384, 248, 660, 524), "2 bronze-gold broadsword cleaving ochre mountain rock waves"),
        (im_ic_ex, icons_extra_src, "project/assets/ui/icons/sk_taunt_bell.png", (716, 248, 992, 524), "Q antique bronze guardian bell radiating amber soundwaves"),
        (im_ic_ex, icons_extra_src, "project/assets/ui/icons/item_dew.png", (1048, 248, 1324, 524), "6 celadon-jade double-bulb gourd with luminous spring-dew droplet"),
    ]
    for src_arr, src_p, ic_rel, (x0, y0, x1, y1), desc in icon_jobs:
        arr96 = frame_xuan_icon_96(src_arr[y0:y1, x0:x1])
        Image.fromarray(arr96, mode="RGBA").save(REPO_ROOT / ic_rel, format="PNG", optimize=False)
        updates.append(
            {
                "path": ic_rel,
                "source_path": src_p,
                "category": "ui_icon",
                "creation_method": (
                    f"Gemini Imagen (2026-11-28, Song-Ming Gongbi warm Xuan-parchment skill/item icon: {desc}) + "
                    f"tools/build_polish_r8_gait_town_and_hud.py 96x96 chamfered bronze framing"
                ),
                "license": LIC_R8,
            }
        )

    return updates


def update_manifest(entries: list[dict[str, str]]) -> None:
    manifest_path = REPO_ROOT / "docs/asset-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    by_path = {item["path"]: item for item in manifest["assets"]}

    for spec in entries:
        rel = spec["path"]
        abs_f = REPO_ROOT / rel
        sha = hashlib.sha256(abs_f.read_bytes()).hexdigest()
        rec = {
            "path": rel,
            "source_path": spec["source_path"],
            "category": spec["category"],
            "creation_method": spec["creation_method"],
            "license": spec["license"],
            "sha256": sha,
        }
        by_path[rel] = rec

    manifest["assets"] = [by_path[k] for k in sorted(by_path.keys())]
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"[build_polish_r8_gait_town_and_hud] Updated {len(entries)} R8 assets cleanly (manifest={len(manifest['assets'])}).")


def main() -> int:
    all_updates: list[dict[str, str]] = []
    all_updates.extend(build_r8_party_hero_sheets())
    all_updates.extend(build_r8_multipose_enemies_and_fox())
    all_updates.extend(build_r8_town_and_hud_assets())
    update_manifest(all_updates)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
