#!/usr/bin/env python3
"""
Deterministic Song-Ming Gongbi World & Lighting Asset Builder for Milestone M4 (Polish R4 — Round 2).
Strictly aligns with AGENTS.md, 20-art-bible.md, 12-exploration-and-levels.md, and
docs/reviews/gate3_masters/master_a_tingyu_town.png:
- Generates 13 world architectural, cave/pass landmark, foreground parallax, and radial light PNGs
  under project/assets/world/ (all <= 1024px, 0 fluorescent neon pixels).
- Enforces canonical Simplified Chinese plaque '济世药庐' on prop_yaolu_gatehouse.png with generous margins.
- Saves provenance contact sheet & spec JSON under assets_src/world/ and updates docs/asset-manifest.json.
"""

from __future__ import annotations

import hashlib
import json
import math
import os
from typing import Any

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SOURCE_SHEET_REL = "assets_src/world/r4_world_lighting_source.png"
SOURCE_SPEC_REL = "assets_src/world/r4_world_lighting_spec.json"
GEN_DATE = "2026-04-12"
LICENSE_R4 = "Project Original Procedural Song-Ming Gongbi World Art (CC0 / Proprietary Clean)"
FONT_BOLD_PATH = os.path.join(REPO_ROOT, "project/assets/fonts/NotoSerifCJKsc-Bold.otf")

# Song-Ming Mineral & Jiangnan Ink Palette (matched to prop_yaolu_hall.png & master_a_tingyu_town.png)
COL_INK = (26, 26, 25, 255)
COL_INK_SOFT = (46, 48, 46, 255)
COL_WALL_LIGHT = (212, 203, 186, 255)
COL_WALL_WARM = (198, 187, 168, 255)
COL_WALL_SHADE = (172, 164, 148, 255)
COL_WALL_EAVE_SHADE = (142, 134, 120, 255)
COL_WALL_DAMP = (138, 138, 126, 255)
COL_TILE_DARK = (46, 54, 58, 255)
COL_TILE_MID = (66, 76, 82, 255)
COL_TILE_HI = (94, 106, 112, 255)
COL_TIMBER_DARK = (70, 50, 36, 255)
COL_TIMBER_MID = (108, 78, 54, 255)
COL_TIMBER_LIGHT = (140, 106, 74, 255)
COL_WINDOW_GLOW = (182, 146, 94, 255)
COL_THATCH_DARK = (112, 92, 54, 255)
COL_THATCH_MID = (150, 128, 78, 255)
COL_THATCH_HI = (176, 154, 98, 255)
COL_STONE_DARK = (66, 74, 72, 255)
COL_STONE_MID = (98, 108, 104, 255)
COL_STONE_HI = (132, 140, 132, 255)
COL_MOSS = (76, 104, 78, 255)


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        while True:
            chunk = fh.read(65536)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def count_fluorescent_pixels(
    arr: np.ndarray, val_thresh: int = 245, sat_thresh: float = 0.92
) -> int:
    rgb = arr[..., :3].astype(np.float32)
    if arr.shape[-1] == 4:
        vis = arr[..., 3] >= 48
    else:
        vis = np.ones(arr.shape[:2], dtype=bool)
    cmax = rgb.max(axis=-1)
    cmin = rgb.min(axis=-1)
    sat = np.where(cmax > 1e-5, (cmax - cmin) / np.maximum(cmax, 1.0), 0.0)
    mask = vis & (cmax >= float(val_thresh)) & (sat >= sat_thresh)
    return int(mask.sum())


def clamp_song_ming_mineral_hsv(arr: np.ndarray) -> np.ndarray:
    out = arr.copy()
    rgb = out[..., :3].astype(np.float32) / 255.0
    cmax = rgb.max(axis=-1)
    cmin = rgb.min(axis=-1)
    delta = cmax - cmin

    sat = np.where(cmax > 1e-5, delta / np.maximum(cmax, 1e-5), 0.0)
    val = cmax

    bright_mask = val > 0.86
    max_sat = np.where(bright_mask, 0.70, 0.78)
    sat_clamped = np.minimum(sat, max_sat)
    val_clamped = np.minimum(val, 0.91)

    scale_s = np.where(sat > 1e-5, sat_clamped / np.maximum(sat, 1e-5), 0.0)
    rgb_desat = cmax[..., None] - (cmax[..., None] - rgb) * scale_s[..., None]
    scale_v = np.where(cmax > 1e-5, val_clamped / np.maximum(cmax, 1e-5), 0.0)
    rgb_final = np.clip(np.round(rgb_desat * scale_v[..., None] * 255.0), 0, 255).astype(
        np.uint8
    )
    out[..., :3] = rgb_final
    return out


def save_rgba_deterministic(arr: np.ndarray, full_path: str) -> None:
    os.makedirs(os.path.dirname(full_path), exist_ok=True)
    clean = clamp_song_ming_mineral_hsv(arr)
    Image.fromarray(clean, mode="RGBA").save(full_path, format="PNG", optimize=False)


def save_rgb_deterministic(arr: np.ndarray, full_path: str) -> None:
    os.makedirs(os.path.dirname(full_path), exist_ok=True)
    clean = clamp_song_ming_mineral_hsv(arr[..., :3])
    Image.fromarray(clean, mode="RGB").save(full_path, format="PNG", optimize=False)


def _add_paper_weathering(im: Image.Image, seed: int = 17, strength: float = 7.5) -> np.ndarray:
    arr = np.array(im.convert("RGBA"), dtype=np.float32)
    rng = np.random.default_rng(seed)
    h, w = arr.shape[:2]
    coarse = rng.normal(0.0, 1.0, (max(4, h // 5), max(4, w // 5))).astype(np.float32)
    fine = rng.normal(0.0, 1.0, (max(8, h // 2), max(8, w // 2))).astype(np.float32)
    c_img = Image.fromarray(np.clip((coarse * 0.25 + 0.5) * 255.0, 0, 255).astype(np.uint8))
    f_img = Image.fromarray(np.clip((fine * 0.25 + 0.5) * 255.0, 0, 255).astype(np.uint8))
    grain_c = (np.array(c_img.resize((w, h), Image.Resampling.BILINEAR), dtype=np.float32) / 255.0 - 0.5) * 2.0
    grain_f = (np.array(f_img.resize((w, h), Image.Resampling.BILINEAR), dtype=np.float32) / 255.0 - 0.5) * 2.0
    grain = grain_c * 0.72 + grain_f * 0.28
    vis = arr[..., 3] > 16
    for ch in range(3):
        arr[..., ch] = np.where(vis, np.clip(arr[..., ch] + grain * strength, 0.0, 255.0), arr[..., ch])
    return arr.astype(np.uint8)


def _quad_pt(
    tl: np.ndarray,
    tr: np.ndarray,
    br: np.ndarray,
    bl: np.ndarray,
    u: float,
    v: float,
    sag_px: float = 0.0,
    eave_lift_px: float = 0.0,
) -> tuple[float, float]:
    """Evaluate Song-Ming concave-sagging & upturned-eave roof surface point."""
    top_u = tl * (1.0 - u) + tr * u
    bot_u = bl * (1.0 - u) + br * u
    p = top_u * (1.0 - v) + bot_u * v
    # Concave slope sag (反宇): deepest around v=0.52
    sag = sag_px * (4.0 * v * (1.0 - v))
    # Upturned flying corner eaves (飞檐翘角) near u=0 or u=1 at lower eave
    edge_u = max(0.0, abs(u - 0.5) * 2.0 - 0.55) / 0.45
    lift = eave_lift_px * (edge_u * edge_u) * (0.35 + 0.65 * v)
    return (float(p[0]), float(p[1]) + sag - lift)


def _draw_curved_roof_tiles(
    d: ImageDraw.ImageDraw,
    quad: list[tuple[float, float]],
    rows: int = 9,
    cols: int = 14,
    base_col: tuple[int, int, int, int] = COL_TILE_MID,
    sag_px: float = 9.0,
    eave_lift_px: float = 12.0,
) -> None:
    """Draw Song-Ming concave-curved fish-scale clay roof with upturned flying eaves."""
    tl, tr, br, bl = [np.array(p, dtype=np.float32) for p in quad]
    # Dense curved boundary polygon so zero straight-line gaps occur
    boundary: list[tuple[float, float]] = []
    steps_u = max(16, cols * 2)
    steps_v = max(12, rows * 2)
    for i in range(steps_u + 1):
        boundary.append(_quad_pt(tl, tr, br, bl, i / float(steps_u), 0.0, sag_px, eave_lift_px))
    for j in range(1, steps_v + 1):
        boundary.append(_quad_pt(tl, tr, br, bl, 1.0, j / float(steps_v), sag_px, eave_lift_px))
    for i in range(steps_u - 1, -1, -1):
        boundary.append(_quad_pt(tl, tr, br, bl, i / float(steps_u), 1.0, sag_px, eave_lift_px))
    for j in range(steps_v - 1, 0, -1):
        boundary.append(_quad_pt(tl, tr, br, bl, 0.0, j / float(steps_v), sag_px, eave_lift_px))
    d.polygon(boundary, fill=base_col, outline=COL_INK)

    # Upper ridge subtle dark shade band
    upper_band: list[tuple[float, float]] = []
    for i in range(steps_u + 1):
        upper_band.append(_quad_pt(tl, tr, br, bl, i / float(steps_u), 0.0, sag_px, eave_lift_px))
    for i in range(steps_u, -1, -1):
        upper_band.append(_quad_pt(tl, tr, br, bl, i / float(steps_u), 0.26, sag_px, eave_lift_px))
    d.polygon(upper_band, fill=COL_TILE_DARK)

    # Curved pan-tile arcs along rows
    for ri in range(1, rows):
        v = ri / float(rows)
        for ci in range(cols):
            u0 = ci / float(cols)
            u1 = (ci + 1) / float(cols)
            pa = _quad_pt(tl, tr, br, bl, u0, v, sag_px, eave_lift_px)
            pm = _quad_pt(tl, tr, br, bl, 0.5 * (u0 + u1), v, sag_px, eave_lift_px)
            pb = _quad_pt(tl, tr, br, bl, u1, v, sag_px, eave_lift_px)
            d.line([pa, (pm[0], pm[1] + 3.2), pb], fill=COL_INK_SOFT, width=2)

    # Curved barrel-tile ribs (筒瓦瓦垄)
    for ci in range(1, cols):
        u = ci / float(cols)
        pts_rib = [
            _quad_pt(tl, tr, br, bl, u, k / 10.0, sag_px, eave_lift_px) for k in range(11)
        ]
        d.line(pts_rib, fill=COL_INK, width=2)
        pts_hi = [(p[0] + 1.8, p[1]) for p in pts_rib]
        d.line(pts_hi, fill=COL_TILE_HI, width=1)

    # Eave drip-tile edge (滴水瓦当) & crisp ink outline
    eave_pts = [
        _quad_pt(tl, tr, br, bl, i / float(steps_u), 1.0, sag_px, eave_lift_px)
        for i in range(steps_u + 1)
    ]
    d.line([(p[0], p[1] - 2.0) for p in eave_pts], fill=COL_TILE_HI, width=3)
    d.line(eave_pts, fill=COL_INK, width=3)
    d.line(boundary + [boundary[0]], fill=COL_INK, width=3)


def _draw_ridge_beam_and_finials(
    d: ImageDraw.ImageDraw,
    p_left: tuple[float, float],
    p_right: tuple[float, float],
    finial_h: float = 22.0,
) -> None:
    """Draw Song-Ming ornament ridge beam & upturned owl-tail finials (正脊与鸱吻)."""
    lx, ly = p_left
    rx, ry = p_right
    pts_top = []
    pts_bot = []
    for i in range(17):
        u = i / 16.0
        bx = lx * (1.0 - u) + rx * u
        by = ly * (1.0 - u) + ry * u + 4.0 * (4.0 * u * (1.0 - u))
        pts_top.append((bx, by - 9.0))
        pts_bot.append((bx, by + 3.0))
    d.polygon(pts_top + pts_bot[::-1], fill=COL_TILE_HI, outline=COL_INK)
    d.line(pts_top, fill=COL_INK, width=2)
    d.line(pts_bot, fill=COL_INK, width=2)

    # Left & right upturned finials (鸱吻)
    for cx, cy, dir_s in [(lx + 3.0, ly - 4.0, -1.0), (rx - 3.0, ry - 4.0, 1.0)]:
        fin = [
            (cx - dir_s * 6.0, cy + 8.0),
            (cx + dir_s * 8.0, cy + 6.0),
            (cx + dir_s * 12.0, cy - finial_h * 0.55),
            (cx + dir_s * 4.0, cy - finial_h),
            (cx - dir_s * 3.0, cy - finial_h * 0.70),
            (cx - dir_s * 6.0, cy - 2.0),
        ]
        d.polygon(fin, fill=COL_TILE_MID, outline=COL_INK)
        d.line([fin[0], fin[3], fin[2]], fill=COL_INK, width=2)


def _draw_thatch_slope(
    d: ImageDraw.ImageDraw,
    quad: list[tuple[float, float]],
    seed: int = 31,
    strands: int = 120,
    sag_px: float = 6.0,
) -> None:
    tl, tr, br, bl = [np.array(p, dtype=np.float32) for p in quad]
    boundary = [
        _quad_pt(tl, tr, br, bl, i / 20.0, 0.0, sag_px, 4.0) for i in range(21)
    ] + [
        _quad_pt(tl, tr, br, bl, 1.0, j / 10.0, sag_px, 4.0) for j in range(1, 11)
    ] + [
        _quad_pt(tl, tr, br, bl, i / 20.0, 1.0, sag_px, 4.0) for i in range(19, -1, -1)
    ] + [
        _quad_pt(tl, tr, br, bl, 0.0, j / 10.0, sag_px, 4.0) for j in range(9, 0, -1)
    ]
    d.polygon(boundary, fill=COL_THATCH_MID, outline=COL_INK)
    # Layered thatch bundle bands
    for band_v in (0.34, 0.68):
        bpts = [_quad_pt(tl, tr, br, bl, i / 18.0, band_v, sag_px, 4.0) for i in range(19)]
        d.line(bpts, fill=COL_THATCH_DARK, width=3)
    rng = np.random.default_rng(seed)
    for _ in range(strands):
        u = float(rng.uniform(0.02, 0.98))
        v0 = float(rng.uniform(0.0, 0.58))
        v1 = min(1.03, v0 + float(rng.uniform(0.28, 0.52)))
        p0 = _quad_pt(tl, tr, br, bl, u, v0, sag_px, 4.0)
        p1 = _quad_pt(tl, tr, br, bl, u, v1, sag_px, 4.0)
        col = COL_THATCH_HI if rng.random() > 0.44 else COL_THATCH_DARK
        d.line([p0, p1], fill=col, width=2)
    d.line(boundary + [boundary[0]], fill=COL_INK, width=3)
    # Bundled reed ridge
    r_pts = [_quad_pt(tl, tr, br, bl, i / 16.0, 0.0, sag_px, 4.0) for i in range(17)]
    d.line(r_pts, fill=COL_THATCH_DARK, width=8)
    d.line(r_pts, fill=COL_INK, width=2)
    for k in range(1, 10):
        pr = _quad_pt(tl, tr, br, bl, k / 10.0, 0.0, sag_px, 4.0)
        d.line([(pr[0] - 2, pr[1] - 5), (pr[0] + 3, pr[1] + 5)], fill=COL_INK, width=2)


def _draw_pillar_with_drum(
    d: ImageDraw.ImageDraw, px: float, py_top: float, py_bot: float, half_w: float = 7.0
) -> None:
    # Stone drum plinth (青石柱础)
    d.ellipse([px - half_w - 5, py_bot - 6, px + half_w + 5, py_bot + 7], fill=COL_STONE_HI, outline=COL_INK, width=2)
    d.rectangle([px - half_w, py_top, px + half_w, py_bot], fill=COL_TIMBER_MID, outline=COL_INK, width=2)
    d.line([(px - half_w + 3, py_top + 2), (px - half_w + 3, py_bot - 2)], fill=COL_TIMBER_LIGHT, width=2)
    d.line([(px + half_w - 2, py_top + 2), (px + half_w - 2, py_bot - 2)], fill=COL_TIMBER_DARK, width=2)


def build_folk_house_a() -> np.ndarray:
    """264x264 Song-Ming 粉墙黛瓦 Jiangnan folk residence A (curved flying eaves, zero gable seam)."""
    S = 2
    W, H = 264 * S, 264 * S
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    # Soft ground contact shadow
    d.polygon([(38, 444), (318, 382), (504, 456), (224, 522)], fill=(18, 22, 22, 92))

    # Left gable wall (粉墙山墙) — peak extends DEEP (y=108) into roof interior so 0 unpainted gap triangles exist!
    gable_pts = [(58, 228), (154, 108), (236, 252), (236, 512), (58, 440)]
    d.polygon(gable_pts, fill=COL_WALL_SHADE, outline=COL_INK)
    # Upper gable eave shadow & timber collar beam (山墙穿枋与悬鱼惹草)
    d.polygon([(58, 228), (154, 108), (236, 252), (236, 276), (154, 146), (58, 252)], fill=COL_WALL_EAVE_SHADE)
    d.polygon([(98, 206), (204, 248), (204, 262), (98, 220)], fill=COL_TIMBER_DARK, outline=COL_INK)
    # Damp wash & cut-bluestone plinth (青石勒脚)
    d.polygon([(58, 384), (236, 456), (236, 474), (58, 402)], fill=COL_WALL_DAMP)
    d.polygon([(58, 402), (236, 474), (236, 512), (58, 440)], fill=COL_STONE_MID, outline=COL_INK)

    # Front courtyard facade wall — top extends into roof interior (y=172..244) for 0 seam
    front_pts = [(236, 246), (484, 184), (484, 444), (236, 512)]
    d.polygon(front_pts, fill=COL_WALL_LIGHT, outline=COL_INK)
    # Soft eave shadow band under front overhang
    d.polygon([(236, 246), (484, 184), (484, 232), (236, 294)], fill=COL_WALL_EAVE_SHADE)
    d.polygon([(236, 294), (484, 232), (484, 252), (236, 314)], fill=COL_WALL_WARM)
    # Lower timber wainscoting & cut-stone plinth
    d.polygon([(236, 418), (484, 352), (484, 404), (236, 472)], fill=COL_TIMBER_MID, outline=COL_INK)
    for wx in range(252, 480, 18):
        wy = 418 - (wx - 236) * 66.0 / 248.0
        d.line([(wx, wy), (wx, wy + 52)], fill=COL_TIMBER_DARK, width=2)
    d.polygon([(236, 472), (484, 404), (484, 444), (236, 512)], fill=COL_STONE_HI, outline=COL_INK)
    for sx in (288, 344, 402, 452):
        sy = 472 - (sx - 236) * 68.0 / 248.0
        d.line([(sx, sy), (sx, sy + 40)], fill=COL_INK_SOFT, width=2)

    # Warm lattice window on left bay + double wooden door on right bay
    win_pts = [(266, 312), (346, 292), (346, 382), (266, 402)]
    d.polygon(win_pts, fill=COL_WINDOW_GLOW, outline=COL_INK)
    for lx in (286, 306, 326):
        ly = 312 - (lx - 266) * 20.0 / 80.0
        d.line([(lx, ly), (lx, ly + 90)], fill=COL_TIMBER_DARK, width=2)
    for ly_off in (28, 58):
        d.line([(266, 312 + ly_off), (346, 292 + ly_off)], fill=COL_TIMBER_DARK, width=2)
    d.line(win_pts + [win_pts[0]], fill=COL_INK, width=3)

    door_pts = [(384, 298), (450, 282), (450, 412), (384, 430)]
    d.polygon(door_pts, fill=COL_TIMBER_DARK, outline=COL_INK)
    d.polygon([(388, 302), (446, 287), (446, 408), (388, 424)], fill=COL_TIMBER_MID, outline=COL_INK)
    d.line([(417, 294), (417, 416)], fill=COL_INK, width=3)

    # Side gable wooden lattice window
    gwin = [(112, 266), (176, 292), (176, 362), (112, 336)]
    d.polygon(gwin, fill=COL_TIMBER_MID, outline=COL_INK)
    for gx in (128, 144, 160):
        gy = 266 + (gx - 112) * 26.0 / 64.0
        d.line([(gx, gy), (gx, gy + 70)], fill=COL_INK, width=2)

    # Timber columns & stone drum bases
    for px0, py_t, py_b in [(60, 232, 440), (236, 256, 510), (364, 224, 476), (482, 192, 444)]:
        _draw_pillar_with_drum(d, px0, py_t, py_b, half_w=6.5)
    d.polygon([(236, 264), (484, 202), (484, 220), (236, 282)], fill=COL_TIMBER_DARK, outline=COL_INK)

    # Stepped bluestone doorstep (青石踏跺)
    d.polygon([(378, 432), (458, 410), (478, 426), (398, 448)], fill=COL_STONE_HI, outline=COL_INK)
    d.polygon([(398, 448), (478, 426), (478, 440), (398, 462)], fill=COL_STONE_DARK, outline=COL_INK)

    # Concave-curved dark clay roof slopes + flying eaves + ridge finials (0 gap!)
    _draw_curved_roof_tiles(d, [(148, 118), (402, 56), (326, 178), (32, 246)], rows=6, cols=12, base_col=COL_TILE_DARK, sag_px=7.0, eave_lift_px=12.0)
    _draw_curved_roof_tiles(d, [(152, 118), (406, 56), (510, 206), (248, 276)], rows=10, cols=15, base_col=COL_TILE_MID, sag_px=10.0, eave_lift_px=14.0)
    # Carved wooden bargeboard along gable verge (博风板与悬鱼)
    d.line([(32, 246), (152, 120), (248, 276)], fill=COL_TIMBER_DARK, width=8)
    d.line([(32, 246), (152, 120), (248, 276)], fill=COL_INK, width=3)
    d.polygon([(146, 134), (158, 134), (162, 156), (152, 168), (142, 156)], fill=COL_TIMBER_LIGHT, outline=COL_INK)
    _draw_ridge_beam_and_finials(d, (150, 116), (406, 54), finial_h=24.0)

    im_1x = im.resize((264, 264), Image.Resampling.LANCZOS)
    return _add_paper_weathering(im_1x, seed=401, strength=6.5)


def build_folk_house_b() -> np.ndarray:
    """224x244 Song-Ming 粉墙黛瓦 veranda shopfront house B with pent-roof awning & warm lantern."""
    S = 2
    W, H = 224 * S, 244 * S
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    d.polygon([(32, 418), (272, 358), (432, 426), (192, 484)], fill=(18, 22, 22, 92))

    # Left whitewashed gable wall — peak extends deep (y=102) into roof interior for 0 seam
    d.polygon([(48, 214), (132, 102), (202, 236), (202, 474), (48, 408)], fill=COL_WALL_SHADE, outline=COL_INK)
    d.polygon([(48, 214), (132, 102), (202, 236), (202, 260), (132, 138), (48, 238)], fill=COL_WALL_EAVE_SHADE)
    d.polygon([(48, 368), (202, 434), (202, 474), (48, 408)], fill=COL_STONE_MID, outline=COL_INK)

    # Main front whitewashed wall & timber shopfront counter
    d.polygon([(202, 234), (412, 180), (412, 412), (202, 474)], fill=COL_WALL_LIGHT, outline=COL_INK)
    d.polygon([(202, 234), (412, 180), (412, 226), (202, 282)], fill=COL_WALL_EAVE_SHADE)
    d.polygon([(202, 434), (412, 374), (412, 412), (202, 474)], fill=COL_STONE_HI, outline=COL_INK)

    # Warm glowing lattice shopfront & wooden counter sill
    d.polygon([(224, 278), (390, 234), (390, 356), (224, 402)], fill=COL_WINDOW_GLOW, outline=COL_INK)
    for bx in (256, 290, 324, 358):
        by = 278 - (bx - 224) * 44.0 / 166.0
        d.line([(bx, by), (bx, by + 122)], fill=COL_TIMBER_DARK, width=3)
    d.polygon([(218, 344), (396, 296), (396, 366), (218, 414)], fill=COL_TIMBER_MID, outline=COL_INK)
    for wx in range(230, 392, 16):
        wy = 344 - (wx - 218) * 48.0 / 178.0
        d.line([(wx, wy), (wx, wy + 68)], fill=COL_TIMBER_DARK, width=2)

    for px0, py_t, py_b in [(50, 218, 408), (202, 240, 472), (410, 188, 412)]:
        _draw_pillar_with_drum(d, px0, py_t, py_b, half_w=6.0)

    # Projecting lower pent-roof awning (挑檐雨搭) & warm oiled-paper lantern
    _draw_curved_roof_tiles(d, [(198, 246), (416, 190), (438, 232), (218, 290)], rows=4, cols=11, base_col=COL_TILE_DARK, sag_px=4.0, eave_lift_px=7.0)
    d.line([(238, 284), (238, 308)], fill=COL_INK, width=2)
    d.ellipse([225, 306, 251, 338], fill=(202, 146, 82, 255), outline=COL_INK, width=2)
    d.rectangle([231, 303, 245, 309], fill=COL_TIMBER_DARK, outline=COL_INK)
    d.line([(238, 338), (238, 348)], fill=(168, 66, 52, 255), width=2)

    # Concave-curved main upper dark-tile roof + ridge finials
    _draw_curved_roof_tiles(d, [(128, 110), (344, 54), (278, 164), (26, 228)], rows=5, cols=10, base_col=COL_TILE_DARK, sag_px=6.0, eave_lift_px=10.0)
    _draw_curved_roof_tiles(d, [(132, 110), (348, 54), (434, 184), (212, 246)], rows=9, cols=13, base_col=COL_TILE_MID, sag_px=8.5, eave_lift_px=12.0)
    d.line([(26, 228), (132, 112), (212, 246)], fill=COL_TIMBER_DARK, width=7)
    d.line([(26, 228), (132, 112), (212, 246)], fill=COL_INK, width=3)
    _draw_ridge_beam_and_finials(d, (130, 108), (348, 52), finial_h=20.0)

    im_1x = im.resize((224, 244), Image.Resampling.LANCZOS)
    return _add_paper_weathering(im_1x, seed=402, strength=6.5)


def build_folk_roof_eave() -> np.ndarray:
    """348x196 close-up foreground street-facing dark-tile roof & upturned flying eave (aligned to master_a bottom-left)."""
    S = 2
    W, H = 348 * S, 196 * S
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    # Street-facing upper timber gable & lattice clerestory on the right side (facing northeast toward the street!)
    d.polygon([(404, 152), (556, 78), (664, 232), (664, 384), (404, 384)], fill=COL_WALL_WARM, outline=COL_INK)
    d.polygon([(404, 152), (556, 78), (664, 232), (664, 268), (556, 122), (404, 194)], fill=COL_WALL_EAVE_SHADE)
    # Timber framing & lattice window facing street
    d.polygon([(466, 224), (612, 182), (612, 344), (466, 382)], fill=COL_TIMBER_MID, outline=COL_INK)
    d.polygon([(482, 238), (596, 204), (596, 316), (482, 350)], fill=COL_WINDOW_GLOW, outline=COL_INK)
    for lx in (508, 534, 560, 582):
        ly = 238 - (lx - 482) * 34.0 / 114.0
        d.line([(lx, ly), (lx, ly + 110)], fill=COL_TIMBER_DARK, width=3)
    for ly_off in (36, 72):
        d.line([(482, 238 + ly_off), (596, 204 + ly_off)], fill=COL_TIMBER_DARK, width=3)
    _draw_pillar_with_drum(d, 424, 186, 384, half_w=8.0)
    _draw_pillar_with_drum(d, 648, 214, 384, half_w=8.0)

    # Broad close-up pitched dark-clay roof slopes sweeping across foreground
    _draw_curved_roof_tiles(
        d,
        [(22, 168), (552, 48), (684, 236), (168, 368)],
        rows=11,
        cols=18,
        base_col=COL_TILE_DARK,
        sag_px=13.0,
        eave_lift_px=18.0,
    )
    # Secondary lower foreground hip eave overlap on bottom-left
    _draw_curved_roof_tiles(
        d,
        [(18, 248), (376, 168), (456, 386), (44, 388)],
        rows=7,
        cols=13,
        base_col=COL_TILE_MID,
        sag_px=9.0,
        eave_lift_px=14.0,
    )
    # Gable verge trim & ornate ridge finials
    d.line([(552, 48), (684, 236)], fill=COL_TIMBER_DARK, width=9)
    d.line([(552, 48), (684, 236)], fill=COL_INK, width=3)
    _draw_ridge_beam_and_finials(d, (26, 166), (554, 46), finial_h=28.0)

    im_1x = im.resize((348, 196), Image.Resampling.LANCZOS)
    return _add_paper_weathering(im_1x, seed=409, strength=6.5)


def build_yaolu_courtyard_wall() -> np.ndarray:
    """196x112 horizontal-baseline 粉墙黛瓦 courtyard wall module (0 diagonal Y-Sort torso inversion!)."""
    S = 2
    W, H = 196 * S, 112 * S
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    # Flat horizontal ground contact shadow along y = 216 (108 in 1x -> 4px from bottom)
    d.rectangle([10, 210, 382, 221], fill=(18, 22, 22, 86))

    # Subtle isometric 3D left end-cap thickness
    d.polygon([(8, 54), (24, 42), (24, 214), (8, 216)], fill=COL_WALL_SHADE, outline=COL_INK)

    # Main whitewashed wall face (strictly horizontal base y=216!)
    d.rectangle([24, 52, 382, 216], fill=COL_WALL_LIGHT, outline=COL_INK, width=2)
    # Eave drip shadow under coping tiles & damp lower wash
    d.rectangle([26, 54, 380, 76], fill=COL_WALL_EAVE_SHADE)
    d.rectangle([26, 152, 380, 168], fill=COL_WALL_DAMP)

    # Carved Jiangnan dark-tile lattice leak-window (什锦漏窗) in center of wall
    lw_box = [142, 88, 264, 142]
    d.rounded_rectangle(lw_box, radius=6, fill=(54, 62, 60, 240), outline=COL_TILE_DARK, width=4)
    d.rounded_rectangle(lw_box, radius=6, outline=COL_INK, width=2)
    # Ice-ray / diamond lattice tracery inside leak-window
    cx_w, cy_w = 203, 115
    d.polygon([(cx_w, 92), (246, cy_w), (cx_w, 138), (160, cy_w)], outline=COL_TILE_HI, width=3)
    d.line([(146, cy_w), (260, cy_w)], fill=COL_TILE_MID, width=2)
    d.line([(cx_w, 90), (cx_w, 140)], fill=COL_TILE_MID, width=2)

    # Lower cut-bluestone dado (青石墙基)
    d.rectangle([24, 168, 382, 216], fill=COL_STONE_MID, outline=COL_INK, width=2)
    d.line([(24, 192), (382, 192)], fill=COL_INK_SOFT, width=2)
    for kx in (84, 144, 204, 264, 324):
        d.line([(kx, 168), (kx, 192)], fill=COL_INK_SOFT, width=2)
        d.line([(kx + 28, 192), (kx + 28, 216)], fill=COL_INK_SOFT, width=2)

    # Curved dark clay tile coping (黛瓦压脊檐顶)
    _draw_curved_roof_tiles(
        d,
        [(14, 22), (380, 22), (388, 60), (18, 60)],
        rows=3,
        cols=15,
        base_col=COL_TILE_MID,
        sag_px=2.0,
        eave_lift_px=4.0,
    )
    d.rectangle([12, 14, 382, 25], fill=COL_TILE_HI, outline=COL_INK, width=2)

    im_1x = im.resize((196, 112), Image.Resampling.LANCZOS)
    return _add_paper_weathering(im_1x, seed=403, strength=5.8)


def build_yaolu_side_wall() -> np.ndarray:
    """84x186 north-south return courtyard wall module for complete east/west compound enclosure."""
    S = 2
    W, H = 84 * S, 186 * S
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    d.rectangle([38, 24, 134, 366], fill=(18, 22, 22, 74))

    # Whitewashed side wall body + south square brick pier (砖柱收头)
    d.rectangle([48, 24, 118, 356], fill=COL_WALL_SHADE, outline=COL_INK, width=2)
    d.rectangle([86, 24, 120, 356], fill=COL_WALL_LIGHT, outline=COL_INK, width=2)
    d.rectangle([48, 304, 120, 356], fill=COL_STONE_MID, outline=COL_INK, width=2)

    # Vertical pitched dark-tile coping along north-south wall top
    d.polygon([(34, 18), (84, 10), (84, 344), (34, 352)], fill=COL_TILE_DARK, outline=COL_INK)
    d.polygon([(84, 10), (134, 18), (134, 352), (84, 344)], fill=COL_TILE_MID, outline=COL_INK)
    for ry in range(28, 344, 22):
        d.line([(36, ry), (84, ry - 6), (132, ry)], fill=COL_INK, width=2)
        d.line([(38, ry + 3), (84, ry - 3), (130, ry + 3)], fill=COL_TILE_HI, width=1)
    d.rectangle([78, 8, 90, 346], fill=COL_TILE_HI, outline=COL_INK, width=2)

    # Capped south brick pier finial at bottom baseline (y=364 -> 182 in 1x)
    d.rectangle([42, 314, 126, 364], fill=COL_WALL_LIGHT, outline=COL_INK, width=2)
    d.rectangle([42, 342, 126, 364], fill=COL_STONE_MID, outline=COL_INK, width=2)
    d.polygon([(32, 316), (84, 296), (136, 316), (128, 326), (40, 326)], fill=COL_TILE_DARK, outline=COL_INK)

    im_1x = im.resize((84, 186), Image.Resampling.LANCZOS)
    return _add_paper_weathering(im_1x, seed=410, strength=5.8)


def build_yaolu_gatehouse() -> np.ndarray:
    """196x188 horizontal-baseline roofed gatehouse with optically centered canonical '济世药庐' plaque."""
    S = 2
    W, H = 196 * S, 188 * S
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    # Threshold stone step at y = 368 (184 in 1x), flush with horizontal courtyard walls!
    d.rectangle([82, 352, 310, 372], fill=COL_STONE_HI, outline=COL_INK, width=2)
    d.rectangle([82, 364, 310, 374], fill=COL_STONE_DARK, outline=COL_INK, width=2)

    # Left & right whitewash stub wings matching prop_yaolu_courtyard_wall height & dado!
    for x0, x1 in [(6, 92), (296, 386)]:
        d.rectangle([x0, 212, x1, 368], fill=COL_WALL_LIGHT, outline=COL_INK, width=2)
        d.rectangle([x0 + 2, 214, x1 - 2, 232], fill=COL_WALL_EAVE_SHADE)
        d.rectangle([x0, 320, x1, 368], fill=COL_STONE_MID, outline=COL_INK, width=2)
        _draw_curved_roof_tiles(
            d,
            [(x0 - 4, 184), (x1 + 4, 184), (x1 + 8, 218), (x0 - 6, 218)],
            rows=3,
            cols=5,
            base_col=COL_TILE_MID,
            sag_px=1.5,
            eave_lift_px=3.0,
        )

    # Heavy timber gate posts, carved brackets & lintel beam (wide open center doorway x=96..292!)
    for px0 in (90, 296):
        _draw_pillar_with_drum(d, px0, 128, 366, half_w=9.0)
    # Inward-swung wooden half-doors leaving clear center passage
    d.polygon([(99, 174), (132, 162), (132, 348), (99, 362)], fill=COL_TIMBER_MID, outline=COL_INK)
    d.polygon([(287, 174), (254, 162), (254, 348), (287, 362)], fill=COL_TIMBER_MID, outline=COL_INK)
    # Cross lintel beams & hanging warm lantern under left bracket
    d.rectangle([82, 134, 304, 158], fill=COL_TIMBER_DARK, outline=COL_INK, width=2)
    d.rectangle([90, 158, 296, 174], fill=COL_TIMBER_MID, outline=COL_INK, width=2)
    d.line([(124, 174), (124, 194)], fill=COL_INK, width=2)
    d.ellipse([112, 192, 136, 220], fill=(204, 148, 82, 255), outline=COL_INK, width=2)

    # Vertical wooden plaque on right wing: canonical Simplified Chinese '济世药庐' (T2-F13-01)
    # Generous vertical & horizontal padding (>= 14px inside inner frame in 2x -> >= 7px in 1x!)
    px0, py0, px1, py1 = 314, 220, 372, 358
    d.rounded_rectangle([px0, py0, px1, py1], radius=6, fill=(188, 152, 102, 255), outline=COL_INK, width=3)
    in_x0, in_y0, in_x1, in_y1 = px0 + 6, py0 + 6, px1 - 6, py1 - 6
    d.rounded_rectangle([in_x0, in_y0, in_x1, in_y1], radius=4, outline=COL_TIMBER_DARK, width=2)
    if os.path.isfile(FONT_BOLD_PATH):
        font = ImageFont.truetype(FONT_BOLD_PATH, 21)
        chars = list("济世药庐")
        usable_h = (in_y1 - in_y0) - 24  # 12px top + 12px bottom breathing margin inside inner border!
        step_y = usable_h / float(len(chars))
        cx_plaque = 0.5 * (in_x0 + in_x1)
        for idx, ch in enumerate(chars):
            bb = d.textbbox((0, 0), ch, font=font)
            gw = bb[2] - bb[0]
            gh = bb[3] - bb[1]
            target_cy = in_y0 + 12.0 + (idx + 0.5) * step_y
            tx = int(round(cx_plaque - gw * 0.5 - bb[0]))
            ty = int(round(target_cy - gh * 0.5 - bb[1]))
            d.text((tx, ty), ch, font=font, fill=COL_INK)

    # Sloped rustic thatch roof over gatehouse (matching master_a_tingyu_town.png)
    _draw_thatch_slope(d, [(54, 24), (338, 24), (358, 72), (34, 72)], seed=411, strands=70, sag_px=3.0)
    _draw_thatch_slope(d, [(48, 30), (344, 30), (374, 144), (18, 144)], seed=412, strands=135, sag_px=7.0)

    im_1x = im.resize((196, 188), Image.Resampling.LANCZOS)
    return _add_paper_weathering(im_1x, seed=404, strength=5.8)


def build_yaolu_alchemy_terrace() -> np.ndarray:
    """312x168 flat cut-bluestone alchemy terrace platform & steps (placed in _ground_decor_layer)."""
    S = 2
    W, H = 312 * S, 168 * S
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    # Contact shadow
    d.polygon([(28, 164), (336, 42), (602, 162), (294, 326)], fill=(16, 20, 20, 96))

    # Isometric bluestone platform top
    top_pts = [(42, 152), (334, 36), (586, 148), (294, 278)]
    d.polygon(top_pts, fill=COL_STONE_HI, outline=COL_INK)
    # Left-south & right-south vertical stone risers
    d.polygon([(42, 152), (294, 278), (294, 304), (42, 178)], fill=COL_STONE_DARK, outline=COL_INK)
    d.polygon([(294, 278), (586, 148), (586, 174), (294, 304)], fill=COL_STONE_MID, outline=COL_INK)

    # Flagstone grid joints on terrace
    tl, tr, br, bl = [np.array(p, dtype=np.float32) for p in top_pts]
    for u in (0.2, 0.4, 0.6, 0.8):
        p0 = tl * (1.0 - u) + tr * u
        p1 = bl * (1.0 - u) + br * u
        d.line([tuple(p0), tuple(p1)], fill=COL_INK_SOFT, width=2)
    for v in (0.25, 0.5, 0.75):
        p0 = tl * (1.0 - v) + bl * v
        p1 = tr * (1.0 - v) + br * v
        d.line([tuple(p0), tuple(p1)], fill=COL_INK_SOFT, width=2)

    # Carved central circular fire-hearth inlay under the bronze cauldron
    d.ellipse([216, 118, 404, 204], fill=COL_STONE_MID, outline=COL_INK, width=2)
    d.ellipse([236, 128, 384, 194], fill=(84, 88, 84, 255), outline=COL_INK_SOFT, width=2)

    # Front-left stepped approach (踏跺石阶, matching master_a)
    for si in range(2):
        ox = 128 - si * 18
        oy = 204 + si * 14
        st_top = [(ox, oy), (ox + 88, oy + 44), (ox + 68, oy + 56), (ox - 20, oy + 12)]
        st_riser = [(ox - 20, oy + 12), (ox + 68, oy + 56), (ox + 68, oy + 70), (ox - 20, oy + 26)]
        d.polygon(st_top, fill=COL_STONE_HI, outline=COL_INK)
        d.polygon(st_riser, fill=COL_STONE_DARK, outline=COL_INK)

    im_1x = im.resize((312, 168), Image.Resampling.LANCZOS)
    return _add_paper_weathering(im_1x, seed=413, strength=5.5)


def build_yaolu_alchemy_pavilion() -> np.ndarray:
    """
    312x308 wide-bay open-sided thatched alchemy pavilion.
    Center bay (1x x in [58, 254], y in [120, 308]) is 100% transparent so prop_alchemy_furnace.png (173x164)
    sits cleanly INSIDE the pavilion beneath the overhanging thatch roof with 0 pillar/eave intersection!
    """
    S = 2
    W, H = 312 * S, 308 * S
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    # Four wide-set timber columns flanking outside the 173px cauldron bay:
    # Left-rear x=58 (1x=29), Left-front x=92 (1x=46) -> cauldron left edge is at 1x=66 (20px clear!)
    # Right-rear x=524 (1x=262), Right-front x=562 (1x=281) -> cauldron right edge is at 1x=240 (22px clear!)
    _draw_pillar_with_drum(d, 58, 176, 488, half_w=7.5)
    _draw_pillar_with_drum(d, 524, 168, 474, half_w=7.5)
    _draw_pillar_with_drum(d, 92, 212, 602, half_w=8.5)
    _draw_pillar_with_drum(d, 562, 204, 592, half_w=8.5)

    # Upper tie-beams & rolled celadon bamboo blind high under the front eave (y <= 232 in 2x -> y <= 116 in 1x!)
    d.polygon([(52, 178), (96, 212), (96, 232), (52, 198)], fill=COL_TIMBER_DARK, outline=COL_INK)
    d.polygon([(520, 170), (568, 204), (568, 224), (520, 190)], fill=COL_TIMBER_DARK, outline=COL_INK)
    d.rectangle([86, 196, 568, 216], fill=COL_TIMBER_DARK, outline=COL_INK, width=2)
    # Rolled celadon-green bamboo blind (青竹卷帘, matching master_a)
    d.rectangle([102, 214, 552, 234], fill=(92, 120, 92, 255), outline=COL_INK, width=2)
    d.line([(102, 224), (552, 224)], fill=COL_INK_SOFT, width=2)
    for tx in (180, 326, 472):
        d.line([(tx, 214), (tx, 238)], fill=(166, 68, 52, 255), width=3)

    # High overarching rustic thatched pavilion roof (lowest eave y <= 230 in 2x -> y <= 115 in 1x, clear above cauldron finial!)
    _draw_thatch_slope(d, [(118, 34), (496, 28), (546, 174), (36, 182)], seed=421, strands=110, sag_px=5.0)
    _draw_thatch_slope(d, [(124, 38), (502, 32), (596, 214), (66, 222)], seed=422, strands=165, sag_px=8.0)

    im_1x = im.resize((312, 308), Image.Resampling.LANCZOS)
    return _add_paper_weathering(im_1x, seed=405, strength=5.8)


def build_mountain_plank_bridge() -> np.ndarray:
    """316x188 mountain cedar plank bridge aligned to pass road slope (-0.34) with stone abutments & guardrails."""
    S = 2
    W, H = 316 * S, 188 * S
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    # Under-bridge timber trestle frames descending into the mountain ravine
    for tx, ty in [(164, 248), (318, 196), (468, 144)]:
        d.polygon([(tx - 10, ty), (tx + 10, ty - 6), (tx + 18, ty + 96), (tx - 4, ty + 102)], fill=COL_TIMBER_DARK, outline=COL_INK)
        d.line([(tx - 16, ty + 48), (tx + 26, ty + 34)], fill=COL_TIMBER_MID, width=5)

    # Deck corners aligned with mountain pass road slope (dx=+436, dy=-150 -> slope = -0.344)
    tl = np.array([62.0, 212.0], dtype=np.float32)
    tr = np.array([498.0, 62.0], dtype=np.float32)
    br = np.array([572.0, 166.0], dtype=np.float32)
    bl = np.array([136.0, 316.0], dtype=np.float32)

    # Cut-bluestone bridgehead abutments (东西两岸青石桥台)
    for a0, a1, dir_u in [(tl, bl, -1.0), (tr, br, 1.0)]:
        off = np.array([dir_u * 26.0, -dir_u * 9.0], dtype=np.float32)
        ab_top = [tuple(a0), tuple(a0 + off), tuple(a1 + off), tuple(a1)]
        d.polygon(ab_top, fill=COL_STONE_HI, outline=COL_INK)
        ab_side = [tuple(a1), tuple(a1 + off), (a1[0] + off[0], a1[1] + off[1] + 24), (a1[0], a1[1] + 24)]
        d.polygon(ab_side, fill=COL_STONE_DARK, outline=COL_INK)

    # Longitudinal stringer logs under deck
    d.polygon([tuple(bl), tuple(br), (br[0], br[1] + 20), (bl[0], bl[1] + 20)], fill=COL_TIMBER_DARK, outline=COL_INK)

    # 18 transverse wet cedar planks
    n_planks = 18
    rng = np.random.default_rng(430)
    for i in range(n_planks):
        u0 = (i + 0.06) / float(n_planks)
        u1 = (i + 0.91) / float(n_planks)
        p_tl = tl * (1.0 - u0) + tr * u0
        p_tr = tl * (1.0 - u1) + tr * u1
        p_br = bl * (1.0 - u1) + br * u1
        p_bl = bl * (1.0 - u0) + br * u0
        tone = int(rng.integers(-11, 12))
        pcol = (
            max(40, COL_TIMBER_MID[0] + tone),
            max(30, COL_TIMBER_MID[1] + tone),
            max(20, COL_TIMBER_MID[2] + tone),
            255,
        )
        d.polygon([tuple(p_tl), tuple(p_tr), tuple(p_br), tuple(p_bl)], fill=pcol, outline=COL_INK)
        pm0 = 0.5 * (p_tl + p_tr)
        pm1 = 0.5 * (p_bl + p_br)
        d.line([tuple(pm0), tuple(pm1)], fill=COL_TIMBER_LIGHT, width=2)

    # North & south timber posts + double hemp-rope guardrails flanking the road edges
    for (ra, rb), post_h in [((tl, tr), 54.0), ((bl, br), 54.0)]:
        posts_top = []
        posts_mid = []
        for k in range(5):
            u = k / 4.0
            pb = ra * (1.0 - u) + rb * u
            px, py = float(pb[0]), float(pb[1])
            posts_top.append((px, py - post_h + 10.0))
            posts_mid.append((px, py - post_h * 0.45))
            d.rectangle([px - 6, py - post_h, px + 6, py + 6], fill=COL_TIMBER_DARK, outline=COL_INK, width=2)
            d.rectangle([px - 8, py - post_h + 6, px + 8, py - post_h + 15], fill=COL_THATCH_HI, outline=COL_INK)
        for k in range(len(posts_top) - 1):
            p0, p1 = posts_top[k], posts_top[k + 1]
            pm = (0.5 * (p0[0] + p1[0]), 0.5 * (p0[1] + p1[1]) + 7.0)
            d.line([p0, pm, p1], fill=COL_THATCH_MID, width=5)
            d.line([p0, pm, p1], fill=COL_INK, width=1)
            m0, m1 = posts_mid[k], posts_mid[k + 1]
            d.line([m0, m1], fill=COL_TIMBER_MID, width=4)

    im_1x = im.resize((316, 188), Image.Resampling.LANCZOS)
    return _add_paper_weathering(im_1x, seed=406, strength=5.8)


def _catmull_rom_chain(pts: list[tuple[float, float]], samples_per_seg: int = 24) -> list[tuple[float, float]]:
    ext = [pts[0]] + pts + [pts[-1]]
    out: list[tuple[float, float]] = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = [np.array(p, dtype=np.float32) for p in ext[i - 1 : i + 3]]
        for s in range(samples_per_seg):
            t = s / float(samples_per_seg)
            t2 = t * t
            t3 = t2 * t
            q = 0.5 * (
                (2.0 * p1)
                + (-p0 + p2) * t
                + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
                + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
            )
            out.append((float(q[0]), float(q[1])))
    out.append(pts[-1])
    return out


def _draw_organic_root_tube(
    d: ImageDraw.ImageDraw,
    ctrl_pts: list[tuple[float, float]],
    r_start: float,
    r_end: float,
) -> None:
    """Render seamless curved root tube with 0 joint holes via dense overlapping disks + bark grain."""
    curve = _catmull_rom_chain(ctrl_pts, samples_per_seg=28)
    n = len(curve)
    # Pass 1: Dark ink outer silhouette
    for i, (cx, cy) in enumerate(curve):
        u = i / float(max(1, n - 1))
        rad = r_start * (1.0 - u) + r_end * u + 2.2 * math.sin(u * 14.0)
        d.ellipse([cx - rad - 3.0, cy - rad - 3.0, cx + rad + 3.0, cy + rad + 3.0], fill=COL_INK)
    # Pass 2: Deep gnarled wood body
    for i, (cx, cy) in enumerate(curve):
        u = i / float(max(1, n - 1))
        rad = r_start * (1.0 - u) + r_end * u + 2.2 * math.sin(u * 14.0)
        d.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=(64, 48, 36, 255))
    # Pass 3: Gongbi bark highlight & shadow striations along upper-left rim
    hi_pts = []
    sh_pts = []
    for i, (cx, cy) in enumerate(curve):
        u = i / float(max(1, n - 1))
        rad = r_start * (1.0 - u) + r_end * u
        hi_pts.append((cx - rad * 0.36, cy - rad * 0.28))
        sh_pts.append((cx + rad * 0.34, cy + rad * 0.26))
    d.line(hi_pts, fill=(104, 82, 60, 255), width=max(3, int(r_start * 0.42)))
    d.line(sh_pts, fill=(40, 30, 22, 255), width=max(2, int(r_start * 0.32)))


def build_cave_gnarled_roots() -> np.ndarray:
    """284x264 organic spline gnarled ancient roots emerging from cavern crag crown (0 joint gaps, 0 flat cutoffs)."""
    S = 2
    W, H = 284 * S, 264 * S
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    d.ellipse([44, 434, 524, 522], fill=(12, 16, 16, 120))

    # fractured mossy cavern boulder base
    rock_pts = [(62, 488), (112, 352), (268, 306), (446, 352), (508, 480), (372, 520), (162, 518)]
    d.polygon(rock_pts, fill=COL_STONE_DARK, outline=COL_INK)
    d.polygon([(112, 352), (268, 306), (392, 364), (222, 418)], fill=COL_STONE_MID, outline=COL_INK_SOFT)
    d.polygon([(222, 418), (392, 364), (484, 468), (344, 506)], fill=(54, 62, 60, 255), outline=COL_INK)

    # Organic Catmull-Rom root tendrils gripping the boulder (0 straight-segment joint holes!)
    roots = [
        ([(256, 54), (218, 132), (196, 226), (132, 336), (68, 474)], 22.0, 7.0),
        ([(304, 48), (332, 138), (356, 238), (424, 356), (496, 486)], 23.0, 7.5),
        ([(278, 62), (272, 168), (242, 286), (216, 408), (178, 512)], 19.0, 6.5),
        ([(292, 74), (318, 192), (304, 314), (348, 424), (378, 514)], 17.5, 6.0),
        ([(234, 68), (164, 146), (104, 238), (74, 342), (46, 428)], 14.0, 5.0),
        ([(328, 66), (394, 148), (452, 242), (492, 344), (524, 426)], 14.0, 5.0),
    ]
    for pts, rs, re in roots:
        _draw_organic_root_tube(d, pts, rs, re)

    # Overhanging dark cavern rock crown & stalactites at top so roots emerge naturally from stone (0 flat tips!)
    crown_pts = [
        (146, 42), (196, 16), (284, 10), (376, 18), (426, 48),
        (398, 92), (344, 78), (312, 104), (276, 82), (236, 102), (188, 78)
    ]
    d.polygon(crown_pts, fill=COL_STONE_DARK, outline=COL_INK)
    d.polygon([(176, 34), (284, 14), (384, 32), (336, 66), (224, 64)], fill=COL_STONE_MID, outline=COL_INK_SOFT)

    # Moss cushions & subtle spirit-jade lichen on knots
    for mx, my, mrx, mry in [
        (194, 228, 28, 14),
        (348, 246, 30, 15),
        (238, 368, 34, 16),
        (386, 392, 28, 14),
        (122, 416, 24, 12),
        (282, 74, 32, 13),
    ]:
        d.ellipse([mx - mrx, my - mry, mx + mrx, my + mry], fill=COL_MOSS, outline=COL_INK_SOFT)
        d.ellipse([mx - mrx // 2, my - mry // 2, mx + mrx // 3, my + mry // 3], fill=(98, 136, 106, 225))

    im_1x = im.resize((284, 264), Image.Resampling.LANCZOS)
    return _add_paper_weathering(im_1x, seed=407, strength=6.2)


def _draw_cloud_fret_spiral(
    d: ImageDraw.ImageDraw, cx: float, cy: float, ux: tuple[float, float], uy: tuple[float, float], s: float = 11.0
) -> None:
    """Incise crisp squared 云雷纹 (cloud-and-thunder fret) spiral on stone cheek balustrade."""
    def pt(a: float, b: float) -> tuple[float, float]:
        return (cx + ux[0] * a + uy[0] * b, cy + ux[1] * a + uy[1] * b)

    spiral = [
        pt(-s, -s),
        pt(s, -s),
        pt(s, s),
        pt(-s * 0.65, s),
        pt(-s * 0.65, -s * 0.42),
        pt(s * 0.42, -s * 0.42),
        pt(s * 0.42, s * 0.36),
        pt(-s * 0.16, s * 0.36),
    ]
    d.line([(p[0] + 1.5, p[1] + 1.5) for p in spiral], fill=COL_STONE_HI, width=2)
    d.line(spiral, fill=COL_INK, width=3)


def build_cave_stone_steps() -> np.ndarray:
    """212x144 carved mossy cavern stone stairs with prominent 云雷纹 cheek balustrades."""
    S = 2
    W, H = 212 * S, 144 * S
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    d.polygon([(30, 186), (278, 72), (398, 168), (150, 282)], fill=(12, 16, 16, 122))

    # 5 stepped carved stone treads descending from top-right toward bottom-left
    n_steps = 5
    for i in range(n_steps - 1, -1, -1):
        sx = 66 + i * 42
        sy = 202 - i * 26
        tread = [(sx, sy), (sx + 56, sy - 24), (sx + 154, sy + 46), (sx + 98, sy + 70)]
        riser = [(sx, sy), (sx + 98, sy + 70), (sx + 98, sy + 88), (sx, sy + 18)]
        d.polygon(tread, fill=COL_STONE_HI if i % 2 == 0 else COL_STONE_MID, outline=COL_INK)
        d.polygon(riser, fill=COL_STONE_DARK, outline=COL_INK)
        # Chiseled slab joint & moss cushion
        d.line([(sx + 49, sy + 35), (sx + 105, sy + 11)], fill=COL_INK_SOFT, width=2)
        mx = int(sx + 34 + (i % 3) * 20)
        my = int(sy + 22 + (i % 2) * 12)
        d.ellipse([mx - 15, my - 7, mx + 15, my + 7], fill=COL_MOSS)

    # Flanking tall stone cheek balustrades with clear 云雷纹 (cloud-fret) relief carvings!
    for ox, oy in [(44, 188), (150, 262)]:
        curb_top = [(ox, oy), (ox + 224, oy - 108), (ox + 246, oy - 92), (ox + 22, oy + 16)]
        curb_side = [(ox + 22, oy + 16), (ox + 246, oy - 92), (ox + 246, oy - 56), (ox + 22, oy + 52)]
        curb_front = [(ox, oy), (ox + 22, oy + 16), (ox + 22, oy + 52), (ox, oy + 36)]
        d.polygon(curb_top, fill=COL_STONE_HI, outline=COL_INK)
        d.polygon(curb_side, fill=COL_STONE_MID, outline=COL_INK)
        d.polygon(curb_front, fill=COL_STONE_DARK, outline=COL_INK)
        # 4 carved 云雷纹 spirals along the outer cheek face
        ux = (0.894, -0.432)
        uy = (0.0, 1.0)
        for k in range(4):
            u = (k + 0.5) / 4.0
            cx = (ox + 22) * (1.0 - u) + (ox + 246) * u
            cy = (oy + 34) * (1.0 - u) + (oy - 74) * u
            _draw_cloud_fret_spiral(d, cx, cy, ux, uy, s=11.5)

    im_1x = im.resize((212, 144), Image.Resampling.LANCZOS)
    return _add_paper_weathering(im_1x, seed=408, strength=5.8)


def build_fg_bamboo_leaf() -> np.ndarray:
    """220x156 corner-rooted Song-Ming calligraphic wind-swept bamboo branch for Layer 3 viewport-edge framing."""
    S = 2
    W, H = 220 * S, 156 * S
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    # Primary & secondary bamboo stalks emerging directly from outer corner (x=0, y=0..44) — zero floating mid-air stem!
    main_stalk = _catmull_rom_chain([(0, 10), (96, 38), (212, 82), (334, 138)], samples_per_seg=18)
    sub_stalk = _catmull_rom_chain([(0, 48), (68, 92), (146, 154), (218, 224)], samples_per_seg=16)
    d.line(main_stalk, fill=(20, 32, 27, 236), width=6)
    d.line(sub_stalk, fill=(22, 35, 30, 224), width=4)
    for nx, ny in [(96, 38), (212, 82), (68, 92), (146, 154)]:
        d.line([(nx - 4, ny - 5), (nx + 4, ny + 5)], fill=(14, 22, 19, 246), width=4)

    leaves = [
        [(76, 30), (162, 8), (268, 12), (174, 34)],
        [(132, 52), (234, 34), (358, 48), (246, 66)],
        [(186, 72), (288, 72), (408, 106), (296, 102)],
        [(248, 98), (332, 118), (422, 172), (324, 142)],
        [(92, 40), (148, 92), (232, 162), (154, 112)],
        [(172, 68), (226, 126), (308, 204), (228, 148)],
        [(52, 80), (118, 116), (196, 178), (116, 136)],
        [(108, 124), (158, 186), (214, 268), (150, 206)],
        [(36, 64), (58, 132), (92, 222), (52, 148)],
    ]
    for lpts in leaves:
        d.polygon(lpts, fill=(24, 40, 34, 234), outline=(15, 24, 21, 242))
        d.line([lpts[0], lpts[2]], fill=(48, 72, 62, 205), width=2)

    im_blur = im.filter(ImageFilter.GaussianBlur(radius=1.2))
    im_1x = im_blur.resize((220, 156), Image.Resampling.LANCZOS)
    return clamp_song_ming_mineral_hsv(np.array(im_1x, dtype=np.uint8))


def build_light_radial_soft() -> np.ndarray:
    """256x256 smooth cosine-squared radial PointLight2D texture (0 fluorescent pixels, zero hard box edge)."""
    N = 256
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    cx = (N - 1) * 0.5
    cy = (N - 1) * 0.5
    r = np.sqrt(((xx - cx) / cx) ** 2 + ((yy - cy) / cy) ** 2)
    t = np.clip(1.0 - r, 0.0, 1.0)
    falloff = (t * t) * (3.0 - 2.0 * t) * t
    arr = np.zeros((N, N, 4), dtype=np.uint8)
    arr[..., 0] = np.clip(np.round(232.0 * falloff), 0, 232).astype(np.uint8)
    arr[..., 1] = np.clip(np.round(230.0 * falloff), 0, 230).astype(np.uint8)
    arr[..., 2] = np.clip(np.round(224.0 * falloff), 0, 224).astype(np.uint8)
    arr[..., 3] = np.clip(np.round(255.0 * falloff), 0, 255).astype(np.uint8)
    return arr


def build_provenance_contact_sheet(raw_arrays: dict[str, np.ndarray]) -> np.ndarray:
    cols = 4
    keys = sorted(raw_arrays.keys())
    rows = int(math.ceil(len(keys) / float(cols)))
    cell_w, cell_h = 360, 320
    sheet = Image.new("RGB", (cols * cell_w, rows * cell_h), (28, 30, 30))
    d = ImageDraw.Draw(sheet)
    label_font = ImageFont.truetype(FONT_BOLD_PATH, 14) if os.path.isfile(FONT_BOLD_PATH) else None
    for idx, rel_p in enumerate(keys):
        r = idx // cols
        c = idx % cols
        ox, oy = c * cell_w, r * cell_h
        d.rectangle([ox + 4, oy + 4, ox + cell_w - 5, oy + cell_h - 5], fill=(42, 46, 45), outline=(96, 86, 66))
        rgba = Image.fromarray(raw_arrays[rel_p], mode="RGBA")
        scale = min((cell_w - 28) / max(1, rgba.width), (cell_h - 46) / max(1, rgba.height), 1.0)
        nw = max(1, int(round(rgba.width * scale)))
        nh = max(1, int(round(rgba.height * scale)))
        thumb = rgba.resize((nw, nh), Image.Resampling.LANCZOS)
        px = ox + (cell_w - nw) // 2
        py = oy + 12 + (cell_h - 44 - nh) // 2
        sheet.paste(thumb.convert("RGB"), (px, py), thumb.split()[3])
        if label_font is not None:
            d.text((ox + 12, oy + cell_h - 26), os.path.basename(rel_p), font=label_font, fill=(214, 204, 184))
        else:
            d.text((ox + 12, oy + cell_h - 24), os.path.basename(rel_p), fill=(214, 204, 184))
    return np.array(sheet, dtype=np.uint8)


def update_asset_manifest(meta_list: list[dict[str, str]]) -> int:
    manifest_path = os.path.join(REPO_ROOT, "docs", "asset-manifest.json")
    with open(manifest_path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)

    by_path: dict[str, dict[str, Any]] = {
        str(entry["path"]): entry for entry in doc.get("assets", [])
    }
    for m in meta_list:
        rel_p = m["path"]
        full_p = os.path.join(REPO_ROOT, rel_p)
        with Image.open(full_p) as im:
            dims = f"{im.width}x{im.height}"
        by_path[rel_p] = {
            "path": rel_p,
            "source_path": SOURCE_SHEET_REL,
            "category": m["category"],
            "dimensions": dims,
            "sha256": sha256_file(full_p),
            "creation_method": m["creation_method"],
            "generated_date": GEN_DATE,
            "license": LICENSE_R4,
        }

    doc["assets"] = [by_path[k] for k in sorted(by_path.keys())]
    with open(manifest_path, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    return len(doc["assets"])


def build_all() -> None:
    generated: dict[str, tuple[np.ndarray, str, str]] = {
        "project/assets/world/prop_folk_house_a.png": (
            build_folk_house_a(),
            "world_prop",
            "tools/build_polish_r4_world.py (2x-supersampled Song-Ming 粉墙黛瓦 Jiangnan curved-eave folk residence A aligned to master_a_tingyu_town.png)",
        ),
        "project/assets/world/prop_folk_house_b.png": (
            build_folk_house_b(),
            "world_prop",
            "tools/build_polish_r4_world.py (2x-supersampled Song-Ming 粉墙黛瓦 Jiangnan eave-veranda folk residence B with hanging paper lantern)",
        ),
        "project/assets/world/prop_folk_roof_eave.png": (
            build_folk_roof_eave(),
            "world_prop",
            "tools/build_polish_r4_world.py (2x-supersampled close-up foreground street-facing dark-tile roof & upturned flying eave aligned to master_a bottom-left)",
        ),
        "project/assets/world/prop_yaolu_courtyard_wall.png": (
            build_yaolu_courtyard_wall(),
            "world_prop",
            "tools/build_polish_r4_world.py (2x-supersampled horizontal-baseline whitewashed courtyard wall with Jiangnan lattice leak-window & curved dark-tile coping)",
        ),
        "project/assets/world/prop_yaolu_side_wall.png": (
            build_yaolu_side_wall(),
            "world_prop",
            "tools/build_polish_r4_world.py (2x-supersampled north-south whitewashed courtyard return wall with brick corner pier & dark-tile coping)",
        ),
        "project/assets/world/prop_yaolu_gatehouse.png": (
            build_yaolu_gatehouse(),
            "world_prop",
            "tools/build_polish_r4_world.py (2x-supersampled timber & thatch courtyard gatehouse with optically centered Simplified Chinese '济世药庐' plaque)",
        ),
        "project/assets/world/prop_yaolu_alchemy_terrace.png": (
            build_yaolu_alchemy_terrace(),
            "world_prop",
            "tools/build_polish_r4_world.py (2x-supersampled cut-bluestone alchemy terrace platform & steps for 济世药庐 cauldron)",
        ),
        "project/assets/world/prop_yaolu_alchemy_pavilion.png": (
            build_yaolu_alchemy_pavilion(),
            "world_prop",
            "tools/build_polish_r4_world.py (2x-supersampled wide-bay open thatched alchemy pavilion with rolled celadon bamboo blind framing cauldron cleanly inside)",
        ),
        "project/assets/world/prop_mountain_plank_bridge.png": (
            build_mountain_plank_bridge(),
            "world_prop",
            "tools/build_polish_r4_world.py (2x-supersampled wet cedar mountain plank bridge with stone abutments & hemp-bound guardrails aligned to qinglan_pass)",
        ),
        "project/assets/world/prop_cave_gnarled_roots.png": (
            build_cave_gnarled_roots(),
            "world_prop",
            "tools/build_polish_r4_world.py (2x-supersampled Catmull-Rom organic gnarled ancient roots & cavern stalactite crag aligned to master_b_cangmu_rtwp.png)",
        ),
        "project/assets/world/prop_cave_stone_steps.png": (
            build_cave_stone_steps(),
            "world_prop",
            "tools/build_polish_r4_world.py (2x-supersampled carved mossy cavern stone steps with incised 云雷纹 cloud-fret cheek balustrades)",
        ),
        "project/assets/world/fg_bamboo_leaf.png": (
            build_fg_bamboo_leaf(),
            "world_prop",
            "tools/build_polish_r4_world.py (2x-supersampled Song-Ming calligraphic wind-blown foreground bamboo leaf cluster with soft lens blur)",
        ),
        "project/assets/world/light_radial_soft.png": (
            build_light_radial_soft(),
            "world_light",
            "tools/build_polish_r4_world.py (256x256 C2-smooth radial PointLight2D attenuation texture for Stage C warm/cool dynamic lighting)",
        ),
    }

    meta_entries: list[dict[str, str]] = []
    raw_for_sheet: dict[str, np.ndarray] = {}

    for rel_p in sorted(generated.keys()):
        arr, cat, method = generated[rel_p]
        full_p = os.path.join(REPO_ROOT, rel_p)
        save_rgba_deterministic(arr, full_p)
        with Image.open(full_p) as verify_im:
            v_arr = np.array(verify_im.convert("RGBA"), dtype=np.uint8)
            neon = count_fluorescent_pixels(v_arr)
            assert neon == 0, f"Fluorescent pixel guard failed on {rel_p}: {neon}"
            assert verify_im.width <= 1024 and verify_im.height <= 1024, f"Oversized world tex: {rel_p}"
            raw_for_sheet[rel_p] = v_arr
        meta_entries.append({"path": rel_p, "category": cat, "creation_method": method})

    sheet_arr = build_provenance_contact_sheet(raw_for_sheet)
    save_rgb_deterministic(sheet_arr, os.path.join(REPO_ROOT, SOURCE_SHEET_REL))

    spec_payload = {
        "milestone": "M4 Polish R4 — 3-Zone World Richness, Stage C Dynamic PointLight2D & Wet Bluestone (Round 2)",
        "generated_date": GEN_DATE,
        "benchmark_master": "docs/reviews/gate3_masters/master_a_tingyu_town.png",
        "canonical_plaque_text": "济世药庐",
        "assets": [
            {
                "path": m["path"],
                "category": m["category"],
                "sha256": sha256_file(os.path.join(REPO_ROOT, m["path"])),
            }
            for m in meta_entries
        ],
    }
    spec_path = os.path.join(REPO_ROOT, SOURCE_SPEC_REL)
    os.makedirs(os.path.dirname(spec_path), exist_ok=True)
    with open(spec_path, "w", encoding="utf-8") as fh:
        json.dump(spec_payload, fh, ensure_ascii=False, indent=2)
        fh.write("\n")

    total = update_asset_manifest(meta_entries)
    print(f"[build_polish_r4_world] Generated {len(meta_entries)} deterministic M4 assets (manifest total={total}, 0 fluorescent px).")


if __name__ == "__main__":
    build_all()
