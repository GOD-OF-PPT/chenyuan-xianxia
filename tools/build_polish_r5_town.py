#!/usr/bin/env python3
"""
Polish R5 Town Visual Refinement Asset Builder for 《尘缘问道》 (v0.1.5-slice).
Addresses all playtest screenshot visual issues in tingyu_town while strictly
complying with AGENTS.md, 20-art-bible.md, and docs/asset-manifest.json:
1. Authentic 35-deg Song-Ming Gongbi Jiangnan 粉墙黛瓦 folk houses (prop_folk_house_a,
   prop_folk_house_b, and complete full-foundation prop_folk_roof_eave with zero cut-off bottom).
2. Cohesive 35-deg isometric 济世药庐 gatehouse (with canonical Simplified Chinese '济世药庐'
   plaque & hanging warm lantern), wide-bay thatched alchemy pavilion (zero cauldron/halo pillar
   overlap), and 35-deg modular courtyard straight & corner walls.
3. Physical warm lantern sources composited onto prop_tea_pavilion.png & prop_peddler_stall.png.
4. Uncut, non-neon Song-Ming celadon-malachite prop_spirit_herb_node.png & prop_town_rockery.png.
5. Non-repeating seamless 1024x1024 rainy Song-Ming moss-meadow ground tile (tex_moss_earth.png).
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
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

sys.path.insert(0, os.path.dirname(__file__))
from build_polish_r4_world import (
    FONT_BOLD_PATH,
    REPO_ROOT,
    clamp_song_ming_mineral_hsv,
    count_fluorescent_pixels,
)
from build_step2_assets import apply_song_ming_lut, make_seamless_tile

GEN_DATE = "2026-04-12"
LIC_R5 = (
    "AI-Assisted First-Party Original Asset (Gemini Imagen Song-Ming Gongbi Style-Locked + "
    "tools/build_polish_r5_town.py Cutout, Isometric Plaque Typography & Mineral LUT, Commercial Rights Cleared)"
)


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        while True:
            chunk = fh.read(65536)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def extract_exterior_cutout(
    sub_rgb: np.ndarray,
    bg_rgb: np.ndarray,
    tol: float = 21.0,
    extra_hole_boxes: list[tuple[int, int, int, int]] | None = None,
    erode_fringe: bool = True,
) -> Image.Image:
    """
    Flood-fill ONLY exterior cream background (plus explicit interior openings like doorways),
    preserving 100% of interior creamy whitewashed plaster walls (粉墙) without holes!
    """
    h, w, _ = sub_rgb.shape
    diff = np.linalg.norm(sub_rgb.astype(np.float32) - bg_rgb[None, None, :], axis=-1)
    cream = (diff < tol).astype(np.uint8)
    num, labels, stats, _ = cv2.connectedComponentsWithStats(cream)

    bg_mask = np.zeros((h, w), dtype=bool)
    for cid in range(1, num):
        x, y, cw, ch, _ = stats[cid]
        touches_border = x == 0 or y == 0 or (x + cw >= w) or (y + ch >= h)
        if touches_border:
            bg_mask |= labels == cid
        elif extra_hole_boxes:
            for hx0, hy0, hx1, hy1 in extra_hole_boxes:
                if x >= hx0 and y >= hy0 and (x + cw) <= hx1 and (y + ch) <= hy1:
                    bg_mask |= labels == cid
                    break

    fg_u8 = (~bg_mask).astype(np.uint8) * 255
    # Remove tiny stray exterior specks (< 40 px)
    n_fg, fg_lbl, fg_stats, _ = cv2.connectedComponentsWithStats(fg_u8)
    clean_fg = np.zeros((h, w), dtype=np.uint8)
    for fid in range(1, n_fg):
        if fg_stats[fid, 4] >= 45:
            clean_fg[fg_lbl == fid] = 255

    if erode_fringe:
        # Soft 1px outer defringe so zero cream halo appears against dark wet bluestone
        dist_in = cv2.distanceTransform(clean_fg, cv2.DIST_L2, 3)
        alpha_f = np.clip((dist_in - 0.35) / 1.15, 0.0, 1.0) * 255.0
    else:
        alpha_f = clean_fg.astype(np.float32)

    rgb_f = sub_rgb.astype(np.float32).copy()
    # Pull bright cream boundary pixels gently toward dark Song-Ming ink outline
    rim_mask = (alpha_f > 4.0) & (alpha_f < 238.0) & (diff < tol * 1.65)
    rgb_f[rim_mask] = rgb_f[rim_mask] * 0.42 + np.array([34.0, 36.0, 34.0], dtype=np.float32) * 0.58

    rgba = np.dstack([np.clip(rgb_f, 0, 255).astype(np.uint8), np.clip(alpha_f, 0, 255).astype(np.uint8)])
    ys, xs = np.where(rgba[..., 3] > 12)
    if len(xs) == 0:
        return Image.fromarray(rgba, mode="RGBA")
    return Image.fromarray(rgba[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1], mode="RGBA")


def save_grounded_rgba(
    im_rgba: Image.Image,
    target_w: int,
    target_h: int,
    out_rel: str,
    shadow_alpha: int = 76,
    pad_bot: int = 4,
    lut_sat: float = 0.92,
) -> np.ndarray:
    graded = apply_song_ming_lut(im_rgba, sat_scale=lut_sat)
    resized = graded.resize((target_w, target_h - pad_bot), Image.Resampling.LANCZOS)
    cw, ch = target_w, target_h

    r_arr = np.asarray(resized, dtype=np.float32)
    rh = r_arr.shape[0]
    foot_cut = int(rh * 0.68)
    sil = np.zeros((ch, cw), dtype=np.float32)
    y_dst0 = min(ch, foot_cut + pad_bot)
    copy_h = min(rh - foot_cut, ch - y_dst0)
    if copy_h > 0:
        sil[y_dst0 : y_dst0 + copy_h, :] = (r_arr[foot_cut : foot_cut + copy_h, :, 3] / 255.0) * float(shadow_alpha)
    sil = cv2.GaussianBlur(sil, (13, 7), 3.2)

    sh = np.zeros((ch, cw, 4), dtype=np.uint8)
    sh[..., 0] = 16
    sh[..., 1] = 20
    sh[..., 2] = 19
    sh[..., 3] = np.clip(sil, 0, 255).astype(np.uint8)

    canvas = Image.fromarray(sh, mode="RGBA")
    canvas.alpha_composite(resized, (0, 0))
    final_arr = clamp_song_ming_mineral_hsv(np.asarray(canvas, dtype=np.uint8))
    assert count_fluorescent_pixels(final_arr) == 0, f"Fluorescent pixels in {out_rel}"
    full_p = os.path.join(REPO_ROOT, out_rel)
    os.makedirs(os.path.dirname(full_p), exist_ok=True)
    Image.fromarray(final_arr, mode="RGBA").save(full_p, format="PNG", optimize=False)
    return final_arr


def build_isometric_plaque_text_only(chars: str, w_px: int, h_px: int, shear_y_per_x: float = 0.48) -> Image.Image:
    """
    Render crisp canonical Simplified Chinese '济世药庐' calligraphy at 2x supersampling
    sheared by +0.48 so it fits right inside the hand-drawn wooden signboard frame!
    """
    S = 2
    bw, bh = w_px * S, h_px * S
    card = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)

    if os.path.isfile(FONT_BOLD_PATH):
        font = ImageFont.truetype(FONT_BOLD_PATH, int(bw * 0.62))
        pad_v = int(bh * 0.08)
        usable_h = bh - 2 * pad_v
        step_y = usable_h / float(len(chars))
        cx = bw * 0.5
        for idx, ch in enumerate(chars):
            bb = d.textbbox((0, 0), ch, font=font)
            gw = bb[2] - bb[0]
            gh = bb[3] - bb[1]
            cy = pad_v + (idx + 0.5) * step_y
            tx = int(round(cx - gw * 0.5 - bb[0]))
            ty = int(round(cy - gh * 0.5 - bb[1]))
            d.text((tx, ty), ch, font=font, fill=(26, 21, 18, 250))

    extra_h = int(math.ceil(abs(shear_y_per_x) * bw)) + 4
    src_arr = np.asarray(card, dtype=np.uint8)
    sh_arr = np.zeros((bh + extra_h, bw, 4), dtype=np.uint8)
    for x in range(bw):
        dy = int(round(shear_y_per_x * x)) if shear_y_per_x >= 0 else int(round(abs(shear_y_per_x) * (bw - 1 - x)))
        sh_arr[dy : dy + bh, x, :] = src_arr[:, x, :]

    out_w = w_px
    out_h = max(12, int(round((bh + extra_h) / float(S))))
    return Image.fromarray(sh_arr, mode="RGBA").resize((out_w, out_h), Image.Resampling.LANCZOS)


def build_seamless_moss_meadow() -> np.ndarray:
    """
    Build 1024x1024 seamless rainy Song-Ming moss-meadow texture with ZERO 512px spiky tuft grid:
    Combines 112px-overlap wrapped r5_terrain_moss_meadow_raw.jpg (74%) with 90-deg rotated
    seamless mineral wash terrain_moss_natural_raw.jpg (26%).
    """
    im_r5 = Image.open(os.path.join(REPO_ROOT, "assets_src/world/r5_terrain_moss_meadow_raw.jpg")).convert("RGB")
    out_size = 1024
    overlap = 112
    big = im_r5.resize((out_size + overlap, out_size + overlap), Image.Resampling.LANCZOS)
    arr = np.asarray(big, dtype=np.float32).copy()

    t = (np.arange(overlap, dtype=np.float32) + 0.5) / float(overlap)
    s = t * t * (3.0 - 2.0 * t)
    sx = s[None, :, None]
    arr[:, :overlap, :] = (1.0 - sx) * arr[:, out_size : out_size + overlap, :] + sx * arr[:, :overlap, :]
    arr = arr[:, :out_size, :]

    sy = s[:, None, None]
    arr[:overlap, :, :] = (1.0 - sy) * arr[out_size : out_size + overlap, :] + sy * arr[:overlap, :]
    arr = arr[:out_size, :, :]

    im_nat = Image.open(os.path.join(REPO_ROOT, "assets_src/world/terrain_moss_natural_raw.jpg")).convert("RGB")
    nat_tile = make_seamless_tile(im_nat.rotate(90, expand=False), size=out_size)
    nat_arr = np.asarray(nat_tile, dtype=np.float32)

    blended = arr * 0.74 + nat_arr * 0.26
    mean_c = blended.mean(axis=(0, 1), keepdims=True)
    blended = mean_c + (blended - mean_c) * 0.80
    graded = apply_song_ming_lut(
        Image.fromarray(np.clip(blended, 0, 255).astype(np.uint8), mode="RGB"), sat_scale=0.84
    )
    g = np.asarray(graded, dtype=np.float32)
    g[..., 0] = g[..., 0] * 0.84 + 7.0
    g[..., 1] = g[..., 1] * 0.86 + 10.0
    g[..., 2] = g[..., 2] * 0.85 + 9.0

    rgba_chk = np.dstack([np.clip(g, 0, 255).astype(np.uint8), np.full((out_size, out_size), 255, dtype=np.uint8)])
    clean_rgb = clamp_song_ming_mineral_hsv(rgba_chk)[..., :3]
    assert count_fluorescent_pixels(clean_rgb) == 0, "Fluorescent pixels in tex_moss_earth.png"

    out_rel = "project/assets/world/tex_moss_earth.png"
    Image.fromarray(clean_rgb, mode="RGB").save(os.path.join(REPO_ROOT, out_rel), format="PNG", optimize=False)
    return np.dstack([clean_rgb, np.full((out_size, out_size), 255, dtype=np.uint8)])


def main() -> None:
    generated_thumbs: dict[str, np.ndarray] = {}
    manifest_updates: list[dict[str, str]] = []

    # 1. Three complete 35-deg Song-Ming Gongbi Jiangnan folk houses
    fh_src = "assets_src/world/r5_town_folk_houses_raw.jpg"
    im_fh = np.asarray(Image.open(os.path.join(REPO_ROOT, fh_src)).convert("RGB"))
    bg_fh = np.median(im_fh[:20, :, :], axis=(0, 1))

    house_a_cut = extract_exterior_cutout(im_fh[142:616, 40:504], bg_fh, tol=21.0)
    house_b_cut = extract_exterior_cutout(im_fh[176:598, 515:898], bg_fh, tol=21.0)
    house_c_cut = extract_exterior_cutout(im_fh[173:610, 908:1366], bg_fh, tol=21.0)

    for rel_p, cut_im, tw, th, desc in [
        (
            "project/assets/world/prop_folk_house_a.png",
            house_a_cut,
            282,
            288,
            "Gemini Imagen (r5_town_folk_houses_raw.jpg) + tools/build_polish_r5_town.py exterior cutout & Song-Ming LUT | Spec: 35-deg Jiangnan 粉墙黛瓦 two-bay residence A with stone plinth",
        ),
        (
            "project/assets/world/prop_folk_house_b.png",
            house_b_cut,
            238,
            262,
            "Gemini Imagen (r5_town_folk_houses_raw.jpg) + tools/build_polish_r5_town.py exterior cutout & Song-Ming LUT | Spec: 35-deg Jiangnan 粉墙黛瓦 shopfront house B with awning & warm lantern",
        ),
        (
            "project/assets/world/prop_folk_roof_eave.png",
            house_c_cut,
            292,
            276,
            "Gemini Imagen (r5_town_folk_houses_raw.jpg) + tools/build_polish_r5_town.py exterior cutout & Song-Ming LUT | Spec: 35-deg complete street-side 粉墙黛瓦 courtyard folk house with sweeping double eaves & full bluestone foundation",
        ),
    ]:
        arr = save_grounded_rgba(cut_im, tw, th, rel_p, shadow_alpha=78, pad_bot=4, lut_sat=0.92)
        generated_thumbs[rel_p] = arr
        manifest_updates.append(
            {"path": rel_p, "source_path": fh_src, "category": "world_prop", "creation_method": desc, "license": LIC_R5}
        )

    # 2. 35-deg 济世药庐 Gatehouse (100% unblemished whitewash + canonical '济世药庐' inside native wooden frame!)
    gp_src = "assets_src/world/r5_yaolu_gate_pavilion_raw.jpg"
    im_gp = np.asarray(Image.open(os.path.join(REPO_ROOT, gp_src)).convert("RGB"))
    bg_gp = np.median(im_gp[:20, :, :], axis=(0, 1))

    gate_cut = extract_exterior_cutout(
        im_gp[140:610, 48:485],
        bg_gp,
        tol=19.5,
        extra_hole_boxes=[(175, 180, 286, 382), (80, 110, 185, 225)],
    )
    # Mirror horizontally so gatehouse runs along +0.50 SW courtyard wall facing street (matching master_a!)
    # Native wooden signboard frame in gate_cut (425x455) was at x=306..348, y=184..298 -> after mirror: x=77..119, y=184..298!
    gate_sw = ImageOps.mirror(gate_cut)
    plaque_txt = build_isometric_plaque_text_only("济世药庐", w_px=22, h_px=90, shear_y_per_x=0.46)
    gate_sw.alpha_composite(plaque_txt, (71, 164))

    gate_rel = "project/assets/world/prop_yaolu_gatehouse.png"
    gate_arr = save_grounded_rgba(gate_sw, 268, 284, gate_rel, shadow_alpha=76, pad_bot=4, lut_sat=0.92)
    generated_thumbs[gate_rel] = gate_arr
    manifest_updates.append(
        {
            "path": gate_rel,
            "source_path": gp_src,
            "category": "world_prop",
            "creation_method": "Gemini Imagen (r5_yaolu_gate_pavilion_raw.jpg) + tools/build_polish_r5_town.py 35-deg SW alignment, warm eave lantern & canonical Simplified Chinese '济世药庐' plaque",
            "license": LIC_R5,
        }
    )

    # Alchemy Pavilion: punch out gable truss openings & tuck tiny rear shadow stub so the 207px front-SE bay frames cauldron cleanly
    pav_cut = extract_exterior_cutout(
        im_gp[115:596, 515:990],
        bg_gp,
        tol=19.5,
        extra_hole_boxes=[(85, 165, 175, 240)],
    )
    pav_np = np.asarray(pav_cut, dtype=np.uint8).copy()
    ph_c, pw_c = pav_np.shape[:2]
    pav_np[int(ph_c * 0.45) : int(ph_c * 0.68), int(pw_c * 0.50) : int(pw_c * 0.68), 3] = 0
    pav_rel = "project/assets/world/prop_yaolu_alchemy_pavilion.png"
    pav_arr = save_grounded_rgba(
        Image.fromarray(pav_np, mode="RGBA"), 512, 364, pav_rel, shadow_alpha=68, pad_bot=4, lut_sat=0.92
    )
    generated_thumbs[pav_rel] = pav_arr
    manifest_updates.append(
        {
            "path": pav_rel,
            "source_path": gp_src,
            "category": "world_prop",
            "creation_method": "Gemini Imagen (r5_yaolu_gate_pavilion_raw.jpg) + tools/build_polish_r5_town.py wide-bay open thatched alchemy pavilion with rolled celadon bamboo blind",
            "license": LIC_R5,
        }
    )

    # Roadside Rockery & Dwarf Bamboo
    rock_cut = extract_exterior_cutout(im_gp[212:586, 1008:1336], bg_gp, tol=21.0)
    rock_rel = "project/assets/world/prop_town_rockery.png"
    rock_arr = save_grounded_rgba(rock_cut, 164, 186, rock_rel, shadow_alpha=78, pad_bot=4, lut_sat=0.90)
    generated_thumbs[rock_rel] = rock_arr
    manifest_updates.append(
        {
            "path": rock_rel,
            "source_path": gp_src,
            "category": "world_prop",
            "creation_method": "Gemini Imagen (r5_yaolu_gate_pavilion_raw.jpg) + tools/build_polish_r5_town.py mossy Jiangnan Taihu bluestone rockery & dwarf bamboo",
            "license": LIC_R5,
        }
    )

    # 3. 35-deg Modular Courtyard Wall, Corner Wall & Warm Physical Lanterns
    wl_src = "assets_src/world/r5_yaolu_walls_lanterns_raw.jpg"
    im_wl = np.asarray(Image.open(os.path.join(REPO_ROOT, wl_src)).convert("RGB"))
    bg_wl = np.median(im_wl[:20, :, :], axis=(0, 1))

    wall_cut = extract_exterior_cutout(im_wl[216:598, 48:428], bg_wl, tol=20.0)
    corner_cut = extract_exterior_cutout(im_wl[240:576, 462:908], bg_wl, tol=20.0)
    hang_lantern = extract_exterior_cutout(im_wl[270:554, 958:1084], bg_wl, tol=21.0, extra_hole_boxes=[(0, 0, 126, 75)])
    wind_lantern = extract_exterior_cutout(im_wl[294:562, 1150:1310], bg_wl, tol=21.0, extra_hole_boxes=[(0, 0, 160, 95)])

    wall_rel = "project/assets/world/prop_yaolu_courtyard_wall.png"
    wall_arr = save_grounded_rgba(wall_cut, 136, 138, wall_rel, shadow_alpha=68, pad_bot=3, lut_sat=0.92)
    generated_thumbs[wall_rel] = wall_arr
    manifest_updates.append(
        {
            "path": wall_rel,
            "source_path": wl_src,
            "category": "world_prop",
            "creation_method": "Gemini Imagen (r5_yaolu_walls_lanterns_raw.jpg) + tools/build_polish_r5_town.py 35-deg isometric modular whitewashed brick-base courtyard wall",
            "license": LIC_R5,
        }
    )

    side_rel = "project/assets/world/prop_yaolu_side_wall.png"
    side_arr = save_grounded_rgba(corner_cut, 204, 154, side_rel, shadow_alpha=70, pad_bot=3, lut_sat=0.92)
    generated_thumbs[side_rel] = side_arr
    manifest_updates.append(
        {
            "path": side_rel,
            "source_path": wl_src,
            "category": "world_prop",
            "creation_method": "Gemini Imagen (r5_yaolu_walls_lanterns_raw.jpg) + tools/build_polish_r5_town.py 35-deg isometric V-corner whitewashed courtyard return wall",
            "license": LIC_R5,
        }
    )

    # 4. Composite warm hanging bamboo-paper lantern onto clean prop_tea_pavilion.png (x_min=502 avoids left hall eave; full interior holes cleared!)
    tea_src = "assets_src/world/prop_sheet_buildings_raw.jpg"
    im_bldg = np.asarray(Image.open(os.path.join(REPO_ROOT, tea_src)).convert("RGB"))
    bg_bldg = np.median(im_bldg[:20, :, :], axis=(0, 1))
    tea_sub = im_bldg[160:580, 502:922]
    tea_cut = extract_exterior_cutout(
        tea_sub,
        bg_bldg,
        tol=23.0,
        extra_hole_boxes=[(0, 0, tea_sub.shape[1], tea_sub.shape[0])],
    )
    tea_base = apply_song_ming_lut(tea_cut, sat_scale=0.92).resize((323, 306), Image.Resampling.LANCZOS)
    hl_small = apply_song_ming_lut(hang_lantern, sat_scale=0.95).resize((26, 62), Image.Resampling.LANCZOS)
    tea_canvas = Image.new("RGBA", (323, 306), (0, 0, 0, 0))
    tea_canvas.alpha_composite(tea_base, (0, 0))
    d_tea = ImageDraw.Draw(tea_canvas)
    d_tea.line([(227, 126), (227, 136)], fill=(32, 28, 24, 245), width=2)
    tea_canvas.alpha_composite(hl_small, (214, 134))
    tea_rel = "project/assets/world/prop_tea_pavilion.png"
    tea_arr = save_grounded_rgba(tea_canvas, 323, 310, tea_rel, shadow_alpha=72, pad_bot=4, lut_sat=1.0)
    generated_thumbs[tea_rel] = tea_arr
    manifest_updates.append(
        {
            "path": tea_rel,
            "source_path": tea_src,
            "category": "world_ysort_building",
            "creation_method": "Gemini Imagen (prop_sheet_buildings_raw.jpg + r5_yaolu_walls_lanterns_raw.jpg) + tools/build_polish_r5_town.py hanging bamboo-paper eave lantern composite",
            "license": LIC_R5,
        }
    )

    # 5. Composite portable Daoist wind lantern + soft Gaussian straw-mat shadow onto prop_peddler_stall.png
    int_src = "assets_src/world/prop_sheet_interactables_raw.jpg"
    im_int = np.asarray(Image.open(os.path.join(REPO_ROOT, int_src)).convert("RGB"))
    bg_int = np.median(im_int[:20, :, :], axis=(0, 1))
    stall_cut = extract_exterior_cutout(im_int[65:370, 820:1335], bg_int, tol=22.0)
    stall_base = apply_song_ming_lut(stall_cut, sat_scale=0.92).resize((268, 142), Image.Resampling.LANCZOS)
    wl_small = apply_song_ming_lut(wind_lantern, sat_scale=0.95).resize((34, 58), Image.Resampling.LANCZOS)
    stall_canvas = Image.new("RGBA", (274, 150), (0, 0, 0, 0))
    stall_canvas.alpha_composite(stall_base, (3, 4))
    # Soft warm-umber blurred contact shadow right under the lantern feet (blends naturally into woven straw!)
    sh_layer = Image.new("RGBA", (274, 150), (0, 0, 0, 0))
    ImageDraw.Draw(sh_layer).ellipse([153, 59, 189, 73], fill=(42, 30, 18, 105))
    sh_layer = sh_layer.filter(ImageFilter.GaussianBlur(radius=3.5))
    stall_canvas.alpha_composite(sh_layer, (0, 0))
    stall_canvas.alpha_composite(wl_small, (154, 12))
    stall_rel = "project/assets/world/prop_peddler_stall.png"
    stall_arr = save_grounded_rgba(stall_canvas, 274, 154, stall_rel, shadow_alpha=76, pad_bot=4, lut_sat=1.0)
    generated_thumbs[stall_rel] = stall_arr
    manifest_updates.append(
        {
            "path": stall_rel,
            "source_path": int_src,
            "category": "world_prop",
            "creation_method": "Gemini Imagen (prop_sheet_interactables_raw.jpg + r5_yaolu_walls_lanterns_raw.jpg) + tools/build_polish_r5_town.py portable wind-lantern composite & grounded straw-mat shadow",
            "license": LIC_R5,
        }
    )

    # 6. Extract UNCUT prop_spirit_herb_node.png & clear enclosed cream pockets between stems
    hi, wi, _ = im_int.shape
    herb_sub = im_int[int(hi * 0.50) : int(hi * 0.88), int(wi * 0.73) : int(wi * 0.98)].copy()
    diff_bg = np.linalg.norm(herb_sub.astype(np.float32) - bg_int[None, None, :], axis=-1)
    green_excess = herb_sub[..., 1].astype(np.float32) - 0.5 * (
        herb_sub[..., 0].astype(np.float32) + herb_sub[..., 2].astype(np.float32)
    )
    # Replace both outer pale green aura AND enclosed neutral cream pockets (green_excess < 10) with bg_int
    aura_or_cream_pocket = ((diff_bg < 52.0) & (herb_sub[..., 1] > 182) & (green_excess > 12.0)) | (
        (diff_bg < 42.0) & (green_excess < 10.0)
    )
    herb_sub[aura_or_cream_pocket] = bg_int.astype(np.uint8)
    herb_cut = extract_exterior_cutout(
        herb_sub,
        bg_int,
        tol=25.0,
        extra_hole_boxes=[(0, 0, herb_sub.shape[1], herb_sub.shape[0])],
    )
    h_np = np.asarray(herb_cut, dtype=np.float32).copy()
    vis_h = h_np[..., 3] > 8
    h_np[..., 0] = np.where(vis_h, np.clip(h_np[..., 0] * 0.74 + 22.0, 0, 255), h_np[..., 0])
    h_np[..., 1] = np.where(vis_h, np.clip(h_np[..., 1] * 0.68 + 20.0, 0, 255), h_np[..., 1])
    h_np[..., 2] = np.where(vis_h, np.clip(h_np[..., 2] * 0.72 + 20.0, 0, 255), h_np[..., 2])
    herb_clean = Image.fromarray(h_np.astype(np.uint8), mode="RGBA")
    herb_rel = "project/assets/world/prop_spirit_herb_node.png"
    herb_arr = save_grounded_rgba(herb_clean, 88, 82, herb_rel, shadow_alpha=88, pad_bot=5, lut_sat=0.84)
    generated_thumbs[herb_rel] = herb_arr
    manifest_updates.append(
        {
            "path": herb_rel,
            "source_path": int_src,
            "category": "world_prop",
            "creation_method": "Gemini Imagen (prop_sheet_interactables_raw.jpg) + tools/build_polish_r5_town.py uncut bottom-right extraction, stem-gap cutout & Song-Ming mineral celadon LUT",
            "license": LIC_R5,
        }
    )

    # 7. Seamless non-repeating 1024x1024 tex_moss_earth.png
    moss_arr = build_seamless_moss_meadow()
    moss_rel = "project/assets/world/tex_moss_earth.png"
    manifest_updates.append(
        {
            "path": moss_rel,
            "source_path": "assets_src/world/r5_terrain_moss_meadow_raw.jpg",
            "category": "world_terrain",
            "creation_method": "Gemini Imagen (r5_terrain_moss_meadow_raw.jpg + terrain_moss_natural_raw.jpg) + tools/build_polish_r5_town.py 112px cosine-overlap seamless wrap & rainy celadon-olive harmony (0 spiky grid)",
            "license": LIC_R5,
        }
    )

    # 8. Save contact sheet for visual inspection & provenance
    cols = 4
    keys = sorted(generated_thumbs.keys())
    rows = int(math.ceil(len(keys) / float(cols)))
    cw_s, ch_s = 340, 320
    sheet = Image.new("RGB", (cols * cw_s, rows * ch_s), (34, 38, 36))
    ds = ImageDraw.Draw(sheet)
    lfont = ImageFont.truetype(FONT_BOLD_PATH, 14) if os.path.isfile(FONT_BOLD_PATH) else None
    for idx, k in enumerate(keys):
        r, c = idx // cols, idx % cols
        ox, oy = c * cw_s, r * ch_s
        ds.rectangle([ox + 4, oy + 4, ox + cw_s - 5, oy + ch_s - 5], fill=(54, 62, 56), outline=(102, 92, 72))
        rgba = Image.fromarray(generated_thumbs[k], mode="RGBA")
        sc = min((cw_s - 24) / max(1, rgba.width), (ch_s - 44) / max(1, rgba.height), 1.0)
        nw, nh = max(1, int(round(rgba.width * sc))), max(1, int(round(rgba.height * sc)))
        th_im = rgba.resize((nw, nh), Image.Resampling.LANCZOS)
        px = ox + (cw_s - nw) // 2
        py = oy + 10 + (ch_s - 42 - nh) // 2
        sheet.paste(th_im.convert("RGB"), (px, py), th_im.split()[3])
        ds.text((ox + 10, oy + ch_s - 26), os.path.basename(k), font=lfont, fill=(224, 214, 194))
    sheet.save(os.path.join(REPO_ROOT, "assets_src/world/r5_town_refinement_sheet.png"), format="PNG")

    # 9. Update docs/asset-manifest.json
    manifest_path = os.path.join(REPO_ROOT, "docs/asset-manifest.json")
    with open(manifest_path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)
    by_path: dict[str, dict[str, Any]] = {str(e["path"]): e for e in doc.get("assets", [])}

    for m in manifest_updates:
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

    print(f"[build_polish_r5_town] Built {len(manifest_updates)} R5 town assets cleanly (manifest={len(doc['assets'])}, 0 neon px).")


if __name__ == "__main__":
    main()
