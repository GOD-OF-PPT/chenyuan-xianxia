#!/usr/bin/env python3
"""
Deterministic Song-Ming Gongbi World & Lighting Asset Builder for Milestone M4 (Polish R4).
Strictly aligns with AGENTS.md, 20-art-bible.md, 12-exploration-and-levels.md, and
docs/reviews/gate3_masters/master_a_tingyu_town.png:
- Generates 10 world architectural, cave/pass landmark, foreground parallax, and radial light PNGs
  under project/assets/world/ (all <= 1024px, 0 fluorescent neon pixels).
- Enforces canonical Simplified Chinese plaque '济世药庐' on prop_yaolu_gatehouse.png.
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

# Song-Ming Mineral & Jiangnan Ink Palette
COL_INK = (26, 28, 28, 255)
COL_INK_SOFT = (44, 48, 47, 255)
COL_WALL_LIGHT = (212, 205, 190, 255)
COL_WALL_SHADE = (182, 175, 160, 255)
COL_WALL_DAMP = (146, 144, 132, 255)
COL_TILE_DARK = (48, 56, 60, 255)
COL_TILE_MID = (68, 78, 82, 255)
COL_TILE_HI = (94, 106, 110, 255)
COL_TIMBER_DARK = (74, 54, 38, 255)
COL_TIMBER_MID = (108, 80, 56, 255)
COL_TIMBER_LIGHT = (138, 106, 74, 255)
COL_THATCH_DARK = (118, 98, 58, 255)
COL_THATCH_MID = (154, 132, 82, 255)
COL_THATCH_HI = (178, 156, 102, 255)
COL_STONE_DARK = (70, 78, 76, 255)
COL_STONE_MID = (102, 112, 108, 255)
COL_STONE_HI = (132, 142, 136, 255)
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
    max_sat = np.where(bright_mask, 0.72, 0.80)
    sat_clamped = np.minimum(sat, max_sat)
    val_clamped = np.minimum(val, 0.92)

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


def _add_paper_weathering(im: Image.Image, seed: int = 17, strength: float = 7.0) -> np.ndarray:
    arr = np.array(im.convert("RGBA"), dtype=np.float32)
    rng = np.random.default_rng(seed)
    h, w = arr.shape[:2]
    coarse = rng.normal(0.0, 1.0, (max(4, h // 6), max(4, w // 6))).astype(np.float32)
    coarse_img = Image.fromarray(np.clip((coarse * 0.25 + 0.5) * 255.0, 0, 255).astype(np.uint8))
    grain = (
        np.array(coarse_img.resize((w, h), Image.Resampling.BILINEAR), dtype=np.float32) / 255.0
        - 0.5
    ) * 2.0
    vis = arr[..., 3] > 16
    for ch in range(3):
        arr[..., ch] = np.where(vis, np.clip(arr[..., ch] + grain * strength, 0.0, 255.0), arr[..., ch])
    return arr.astype(np.uint8)


def _draw_roof_tiles(
    d: ImageDraw.ImageDraw,
    quad: list[tuple[float, float]],
    rows: int = 9,
    cols: int = 14,
    base_col: tuple[int, int, int, int] = COL_TILE_DARK,
) -> None:
    """Draw isometric dark clay fish-scale roof tiles inside quad [top_left, top_right, bot_right, bot_left]."""
    tl, tr, br, bl = [np.array(p, dtype=np.float32) for p in quad]
    d.polygon([tuple(p) for p in quad], fill=base_col, outline=COL_INK)
    # Column ribs (瓦垄)
    for ci in range(1, cols):
        u = ci / float(cols)
        p_top = tl * (1.0 - u) + tr * u
        p_bot = bl * (1.0 - u) + br * u
        d.line([tuple(p_top), tuple(p_bot)], fill=COL_INK, width=2)
        d.line(
            [(float(p_top[0]) + 1.5, float(p_top[1])), (float(p_bot[0]) + 1.5, float(p_bot[1]))],
            fill=COL_TILE_HI,
            width=1,
        )
    # Curved tile arcs along rows
    for ri in range(1, rows):
        v = ri / float(rows)
        row_l = tl * (1.0 - v) + bl * v
        row_r = tr * (1.0 - v) + br * v
        for ci in range(cols):
            u0 = ci / float(cols)
            u1 = (ci + 1) / float(cols)
            pa = row_l * (1.0 - u0) + row_r * u0
            pb = row_l * (1.0 - u1) + row_r * u1
            pm = 0.5 * (pa + pb) + np.array([0.0, 3.0], dtype=np.float32)
            d.line([tuple(pa), tuple(pm), tuple(pb)], fill=COL_INK_SOFT, width=2)
    # Eave drip edge highlight
    d.line([tuple(bl), tuple(br)], fill=COL_TILE_HI, width=3)
    d.line([tuple(tl), tuple(tr)], fill=COL_TILE_MID, width=5)
    d.line([tuple(tl), tuple(tr)], fill=COL_INK, width=2)


def _draw_thatch_slope(
    d: ImageDraw.ImageDraw,
    quad: list[tuple[float, float]],
    seed: int = 31,
    strands: int = 90,
) -> None:
    tl, tr, br, bl = [np.array(p, dtype=np.float32) for p in quad]
    d.polygon([tuple(p) for p in quad], fill=COL_THATCH_MID, outline=COL_INK)
    rng = np.random.default_rng(seed)
    for _ in range(strands):
        u = float(rng.uniform(0.02, 0.98))
        v0 = float(rng.uniform(0.0, 0.55))
        v1 = min(1.04, v0 + float(rng.uniform(0.32, 0.58)))
        top_u = tl * (1.0 - u) + tr * u
        bot_u = bl * (1.0 - u) + br * u
        p0 = top_u * (1.0 - v0) + bot_u * v0
        p1 = top_u * (1.0 - v1) + bot_u * v1
        col = COL_THATCH_HI if rng.random() > 0.45 else COL_THATCH_DARK
        d.line([tuple(p0), tuple(p1)], fill=col, width=2)
    # Bundled ridge beam
    d.line([tuple(tl), tuple(tr)], fill=COL_THATCH_DARK, width=7)
    d.line([tuple(tl), tuple(tr)], fill=COL_INK, width=2)
    for k in range(1, 9):
        u = k / 9.0
        pr = tl * (1.0 - u) + tr * u
        d.line([(pr[0] - 2, pr[1] - 4), (pr[0] + 2, pr[1] + 4)], fill=COL_INK, width=2)


def build_folk_house_a() -> np.ndarray:
    """316x292 isometric 粉墙黛瓦 Jiangnan folk residence A (aligned to master_a left street)."""
    S = 2
    W, H = 316 * S, 292 * S
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    # Ground contact shadow
    d.polygon([(38, 502), (382, 434), (602, 514), (252, 580)], fill=(18, 22, 22, 92))

    # Left gable wall (粉墙山墙, shaded)
    gable_pts = [(66, 266), (174, 142), (274, 296), (274, 566), (66, 488)]
    d.polygon(gable_pts, fill=COL_WALL_SHADE, outline=COL_INK)
    # Damp lower stone plinth (青石勒脚)
    d.polygon([(66, 444), (274, 520), (274, 566), (66, 488)], fill=COL_STONE_MID, outline=COL_INK)
    d.polygon([(66, 422), (274, 498), (274, 520), (66, 444)], fill=COL_WALL_DAMP)

    # Front courtyard facade wall (粉墙正立面, sunlit/ambient)
    front_pts = [(274, 296), (578, 222), (578, 488), (274, 566)]
    d.polygon(front_pts, fill=COL_WALL_LIGHT, outline=COL_INK)
    d.polygon([(274, 520), (578, 442), (578, 488), (274, 566)], fill=COL_STONE_LIGHT if False else COL_STONE_HI, outline=COL_INK)
    # Stone masonry joints
    for sx in (335, 405, 475, 535):
        sy = int(520 - (sx - 274) * 78.0 / 304.0)
        d.line([(sx, sy), (sx, sy + 44)], fill=COL_INK_SOFT, width=2)

    # Timber pillars & beams (穿斗木构)
    for px0, py_top, py_bot in [(274, 292, 564), (424, 258, 526), (574, 222, 488), (68, 266, 488)]:
        d.rectangle([px0 - 6, py_top, px0 + 6, py_bot], fill=COL_TIMBER_DARK, outline=COL_INK)
    d.polygon([(274, 304), (578, 230), (578, 248), (274, 322)], fill=COL_TIMBER_MID, outline=COL_INK)

    # Carved wooden double door & stone steps on front right bay
    door_pts = [(458, 336), (534, 318), (534, 466), (458, 486)]
    d.polygon(door_pts, fill=COL_TIMBER_MID, outline=COL_INK)
    d.line([(496, 327), (496, 476)], fill=COL_INK, width=3)
    # Lattice window on front left bay
    win_pts = [(312, 344), (398, 323), (398, 412), (312, 433)]
    d.polygon(win_pts, fill=(52, 46, 40, 255), outline=COL_INK)
    for wx in (334, 355, 376):
        wy = int(344 - (wx - 312) * 21.0 / 86.0)
        d.line([(wx, wy), (wx, wy + 88)], fill=COL_TIMBER_LIGHT, width=2)
    for wy_off in (28, 58):
        d.line([(312, 344 + wy_off), (398, 323 + wy_off)], fill=COL_TIMBER_LIGHT, width=2)

    # Small side gable wooden window
    gwin = [(134, 286), (206, 312), (206, 384), (134, 358)]
    d.polygon(gwin, fill=COL_TIMBER_MID, outline=COL_INK)
    for gx in (152, 170, 188):
        gy = int(286 + (gx - 134) * 26.0 / 72.0)
        d.line([(gx, gy), (gx, gy + 70)], fill=COL_INK, width=2)

    # Stone doorstep (青石踏跺)
    d.polygon([(452, 488), (542, 465), (562, 482), (472, 505)], fill=COL_STONE_HI, outline=COL_INK)
    d.polygon([(472, 505), (562, 482), (562, 496), (472, 519)], fill=COL_STONE_DARK, outline=COL_INK)

    # Pitched dark-tile roof (黛瓦双坡悬山顶)
    # Back slope sliver + main front slope + gable verge
    _draw_roof_tiles(d, [(170, 134), (478, 62), (392, 198), (44, 272)], rows=6, cols=12, base_col=COL_TILE_DARK)
    _draw_roof_tiles(d, [(174, 136), (484, 64), (608, 224), (288, 306)], rows=10, cols=16, base_col=COL_TILE_MID)
    # Whitewash horse-head/verge trim & upturned ridge (乌瓦脊兽压边)
    d.polygon([(164, 124), (492, 50), (496, 68), (168, 142)], fill=COL_TILE_HI, outline=COL_INK)
    d.polygon([(156, 110), (176, 122), (170, 142), (150, 132)], fill=COL_TILE_DARK, outline=COL_INK)
    d.polygon([(484, 38), (504, 48), (498, 68), (478, 58)], fill=COL_TILE_DARK, outline=COL_INK)
    d.line([(44, 272), (174, 136), (288, 306)], fill=COL_INK, width=5)

    im_1x = im.resize((316, 292), Image.Resampling.LANCZOS)
    return _add_paper_weathering(im_1x, seed=401, strength=6.0)


def build_folk_house_b() -> np.ndarray:
    """288x276 isometric 粉墙黛瓦 veranda townhouse B with timber eave gallery."""
    S = 2
    W, H = 288 * S, 276 * S
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    d.polygon([(36, 474), (344, 404), (546, 482), (236, 548)], fill=(18, 22, 22, 92))

    # Left whitewashed gable wall
    d.polygon([(58, 248), (158, 136), (248, 274), (248, 536), (58, 462)], fill=COL_WALL_SHADE, outline=COL_INK)
    d.polygon([(58, 422), (248, 494), (248, 536), (58, 462)], fill=COL_STONE_MID, outline=COL_INK)

    # Main front whitewashed wall & timber shopfront counter/veranda
    d.polygon([(248, 274), (528, 206), (528, 464), (248, 536)], fill=COL_WALL_LIGHT, outline=COL_INK)
    d.polygon([(248, 494), (528, 424), (528, 464), (248, 536)], fill=COL_STONE_HI, outline=COL_INK)

    # Timber framing & shuttered wood bays
    d.polygon([(274, 314), (498, 260), (498, 404), (274, 458)], fill=COL_TIMBER_MID, outline=COL_INK)
    for bx in (328, 386, 444):
        by = int(314 - (bx - 274) * 54.0 / 224.0)
        d.line([(bx, by), (bx, by + 144)], fill=COL_INK, width=3)
    d.polygon([(268, 388), (504, 330), (504, 352), (268, 410)], fill=COL_TIMBER_DARK, outline=COL_INK)

    # Projecting lower pent-roof awning (挑檐雨搭) over front bay
    _draw_roof_tiles(d, [(244, 282), (534, 212), (558, 256), (268, 328)], rows=4, cols=12, base_col=COL_TILE_DARK)
    # Warm paper lantern hanging under eave
    d.line([(296, 322), (296, 344)], fill=COL_INK, width=2)
    d.ellipse([284, 342, 308, 372], fill=(204, 146, 78, 255), outline=COL_INK, width=2)

    # Main upper dark-tile roof
    _draw_roof_tiles(d, [(154, 128), (438, 60), (356, 186), (40, 256)], rows=5, cols=11, base_col=COL_TILE_DARK)
    _draw_roof_tiles(d, [(158, 130), (442, 62), (554, 206), (262, 280)], rows=9, cols=14, base_col=COL_TILE_MID)
    d.polygon([(148, 120), (448, 48), (452, 66), (152, 138)], fill=COL_TILE_HI, outline=COL_INK)
    d.line([(40, 256), (158, 130), (262, 280)], fill=COL_INK, width=5)

    im_1x = im.resize((288, 276), Image.Resampling.LANCZOS)
    return _add_paper_weathering(im_1x, seed=402, strength=6.0)


def build_yaolu_courtyard_wall() -> np.ndarray:
    """236x168 isometric whitewashed & dark-tile courtyard wall segment (粉墙黛瓦院墙)."""
    S = 2
    W, H = 236 * S, 168 * S
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    # Bottom baseline reaches y ~ H - 8 (328 in 2x -> 164 in 1x) for clean Y-Sort anchoring
    d.polygon([(34, 256), (428, 318), (448, 332), (52, 270)], fill=(18, 22, 22, 84))

    # Wall side thickness on left
    d.polygon([(36, 118), (64, 106), (64, 260), (36, 272)], fill=COL_WALL_SHADE, outline=COL_INK)
    # Main whitewashed wall face sloping gently in isometric courtyard alignment
    d.polygon([(64, 106), (438, 168), (438, 326), (64, 260)], fill=COL_WALL_LIGHT, outline=COL_INK)
    # Lower cut-bluestone dado (青石墙基)
    d.polygon([(64, 218), (438, 282), (438, 326), (64, 260)], fill=COL_STONE_MID, outline=COL_INK)
    for kx in (128, 196, 264, 332, 396):
        ky = int(218 + (kx - 64) * 64.0 / 374.0)
        d.line([(kx, ky), (kx, ky + 44)], fill=COL_INK_SOFT, width=2)
    d.line([(64, 240), (438, 304)], fill=COL_INK_SOFT, width=2)

    # Dark clay tile coping (黛瓦压脊檐顶)
    _draw_roof_tiles(d, [(50, 74), (430, 136), (452, 178), (68, 116)], rows=3, cols=14, base_col=COL_TILE_MID)
    _draw_roof_tiles(d, [(28, 104), (50, 74), (68, 116), (40, 126)], rows=2, cols=2, base_col=COL_TILE_DARK)
    d.polygon([(46, 66), (434, 128), (436, 140), (48, 78)], fill=COL_TILE_HI, outline=COL_INK)

    im_1x = im.resize((236, 168), Image.Resampling.LANCZOS)
    return _add_paper_weathering(im_1x, seed=403, strength=5.5)


def build_yaolu_gatehouse() -> np.ndarray:
    """244x264 roofed timber & thatch courtyard gatehouse with canonical '济世药庐' plaque."""
    S = 2
    W, H = 244 * S, 264 * S
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    # Threshold stone & subtle ground shadow
    d.polygon([(78, 444), (392, 502), (414, 522), (96, 464)], fill=(18, 22, 22, 88))
    d.polygon([(112, 438), (356, 484), (372, 506), (126, 458)], fill=COL_STONE_HI, outline=COL_INK)
    d.polygon([(126, 458), (372, 506), (372, 520), (126, 472)], fill=COL_STONE_DARK, outline=COL_INK)

    # Flanking whitewash stub walls connecting to courtyard wall
    d.polygon([(34, 266), (122, 282), (122, 456), (34, 440)], fill=COL_WALL_LIGHT, outline=COL_INK)
    d.polygon([(34, 404), (122, 420), (122, 456), (34, 440)], fill=COL_STONE_MID, outline=COL_INK)
    d.polygon([(356, 326), (452, 344), (452, 520), (356, 502)], fill=COL_WALL_LIGHT, outline=COL_INK)
    d.polygon([(356, 466), (452, 484), (452, 520), (356, 502)], fill=COL_STONE_MID, outline=COL_INK)

    # Heavy timber gate posts & lintel beams (leave open walkable doorway in center!)
    d.polygon([(114, 196), (146, 202), (146, 462), (114, 456)], fill=COL_TIMBER_DARK, outline=COL_INK)
    d.polygon([(334, 236), (368, 242), (368, 506), (334, 500)], fill=COL_TIMBER_DARK, outline=COL_INK)
    # Open wooden door leaf swung inward on left
    d.polygon([(146, 256), (190, 244), (190, 444), (146, 456)], fill=COL_TIMBER_MID, outline=COL_INK)
    d.polygon([(114, 210), (368, 256), (368, 286), (114, 240)], fill=COL_TIMBER_MID, outline=COL_INK)

    # Vertical wooden plaque on right wing: strictly canonical Simplified Chinese '济世药庐' (T2-F13-01)
    plaque_box = [382, 352, 434, 476]
    d.rounded_rectangle(plaque_box, radius=6, fill=(184, 148, 98, 255), outline=COL_INK, width=3)
    d.rounded_rectangle([387, 357, 429, 471], radius=4, outline=COL_TIMBER_DARK, width=2)
    if os.path.isfile(FONT_BOLD_PATH):
        font = ImageFont.truetype(FONT_BOLD_PATH, 24)
        for idx, ch in enumerate("济世药庐"):
            cy = 362 + idx * 27
            d.text((396, cy), ch, font=font, fill=COL_INK)

    # Sloped rustic thatch roof over gatehouse (matching master_a_tingyu_town.png gatehouse)
    _draw_thatch_slope(d, [(86, 98), (394, 154), (352, 224), (48, 168)], seed=411, strands=65)
    _draw_thatch_slope(d, [(92, 100), (402, 156), (446, 268), (124, 210)], seed=412, strands=95)
    # Wall coping tiles on stub wings
    _draw_roof_tiles(d, [(24, 244), (116, 260), (124, 286), (30, 270)], rows=2, cols=4, base_col=COL_TILE_MID)
    _draw_roof_tiles(d, [(364, 304), (460, 322), (466, 348), (368, 330)], rows=2, cols=4, base_col=COL_TILE_MID)

    im_1x = im.resize((244, 264), Image.Resampling.LANCZOS)
    return _add_paper_weathering(im_1x, seed=404, strength=5.5)


def build_yaolu_alchemy_pavilion() -> np.ndarray:
    """268x264 open-sided thatched alchemy pavilion framing cauldron on raised stone terrace."""
    S = 2
    W, H = 268 * S, 264 * S
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    # Raised bluestone alchemy terrace platform & steps at bottom baseline (y ~ 520 in 2x)
    d.polygon([(46, 420), (306, 356), (504, 434), (244, 518)], fill=COL_STONE_HI, outline=COL_INK)
    d.polygon([(46, 420), (244, 518), (244, 526), (46, 436)], fill=COL_STONE_DARK, outline=COL_INK)
    d.polygon([(244, 518), (504, 434), (504, 450), (244, 526)], fill=COL_STONE_MID, outline=COL_INK)
    # Terrace flagstone grid lines
    for u in (0.25, 0.5, 0.75):
        p0 = (46 + (306 - 46) * u, 420 + (356 - 420) * u)
        p1 = (244 + (504 - 244) * u, 518 + (434 - 518) * u)
        d.line([p0, p1], fill=COL_INK_SOFT, width=2)

    # Rear herb shelf & bamboo screen between back pillars
    d.polygon([(82, 232), (298, 178), (298, 360), (82, 414)], fill=(196, 188, 170, 235), outline=COL_INK)
    # Rolled celadon-green bamboo blind at upper rear bay (matching master_a)
    d.polygon([(86, 232), (294, 180), (294, 228), (86, 280)], fill=(96, 124, 96, 255), outline=COL_INK)
    for ry in (14, 28, 40):
        d.line([(86, 232 + ry), (294, 180 + ry)], fill=COL_INK_SOFT, width=2)

    # Four timber pavilion pillars (open center bay so cauldron at y+18 stands prominently inside!)
    for px0, py_top, py_bot in [(76, 218, 418), (298, 166, 362), (236, 282, 504), (478, 218, 434)]:
        d.rectangle([px0 - 7, py_top, px0 + 7, py_bot], fill=COL_TIMBER_MID, outline=COL_INK)
        d.ellipse([px0 - 11, py_bot - 6, px0 + 11, py_bot + 6], fill=COL_STONE_DARK, outline=COL_INK)

    # Timber tie-beams
    d.polygon([(72, 224), (304, 168), (484, 224), (484, 240), (302, 186), (72, 240)], fill=COL_TIMBER_DARK, outline=COL_INK)

    # Warm thatched hip/gable pavilion roof (matching master_a_tingyu_town.png thatched alchemy shed)
    _draw_thatch_slope(d, [(154, 108), (386, 52), (312, 174), (42, 236)], seed=421, strands=85)
    _draw_thatch_slope(d, [(158, 110), (392, 54), (514, 218), (242, 288)], seed=422, strands=125)

    im_1x = im.resize((268, 264), Image.Resampling.LANCZOS)
    return _add_paper_weathering(im_1x, seed=405, strength=5.5)


def build_mountain_plank_bridge() -> np.ndarray:
    """336x196 wooden mountain plank bridge (山道栈桥) with timber guardrails & rope bindings."""
    S = 2
    W, H = 336 * S, 196 * S
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    # Under-bridge chasm shadow & timber support trestle beams
    d.polygon([(52, 256), (546, 134), (636, 244), (144, 378)], fill=(14, 18, 18, 138))
    for tx, ty in [(136, 298), (312, 252), (488, 206)]:
        d.polygon([(tx - 12, ty), (tx + 12, ty - 6), (tx + 24, ty + 78), (tx, ty + 84)], fill=COL_TIMBER_DARK, outline=COL_INK)

    # Isometric bridge deck quad: [top_left, top_right, bot_right, bot_left]
    tl = np.array([56.0, 216.0], dtype=np.float32)
    tr = np.array([542.0, 92.0], dtype=np.float32)
    br = np.array([626.0, 196.0], dtype=np.float32)
    bl = np.array([140.0, 322.0], dtype=np.float32)

    # Longitudinal stringer logs
    d.polygon([tuple(bl), tuple(br), (br[0], br[1] + 18), (bl[0], bl[1] + 18)], fill=COL_TIMBER_DARK, outline=COL_INK)

    # 18 transverse wet cedar planks with slight organic spacing
    n_planks = 18
    rng = np.random.default_rng(430)
    for i in range(n_planks):
        u0 = (i + 0.06) / float(n_planks)
        u1 = (i + 0.90) / float(n_planks)
        p_tl = tl * (1.0 - u0) + tr * u0
        p_tr = tl * (1.0 - u1) + tr * u1
        p_br = bl * (1.0 - u1) + br * u1
        p_bl = bl * (1.0 - u0) + br * u0
        tone = int(rng.integers(-10, 11))
        pcol = (
            max(40, COL_TIMBER_MID[0] + tone),
            max(30, COL_TIMBER_MID[1] + tone),
            max(20, COL_TIMBER_MID[2] + tone),
            255,
        )
        d.polygon([tuple(p_tl), tuple(p_tr), tuple(p_br), tuple(p_bl)], fill=pcol, outline=COL_INK)
        pm0 = 0.5 * (p_tl + p_tr)
        pm1 = 0.5 * (p_bl + p_br)
        d.line([tuple(pm0), tuple(pm1)], fill=COL_TIMBER_LIGHT, width=1)

    # Upper & lower timber posts + hemp-rope handrails
    for rail_pair, post_h in [((tl, tr), 58.0), ((bl, br), 58.0)]:
        a, b = rail_pair
        posts = []
        for k in range(5):
            u = k / 4.0
            p_base = a * (1.0 - u) + b * u
            px, py = float(p_base[0]), float(p_base[1])
            posts.append((px, py - post_h + 10.0))
            d.rectangle([px - 6, py - post_h, px + 6, py + 6], fill=COL_TIMBER_DARK, outline=COL_INK)
            # Hemp rope lashing
            d.rectangle([px - 8, py - post_h + 6, px + 8, py - post_h + 15], fill=COL_THATCH_HI, outline=COL_INK)
        for k in range(len(posts) - 1):
            p0, p1 = posts[k], posts[k + 1]
            pm = (0.5 * (p0[0] + p1[0]), 0.5 * (p0[1] + p1[1]) + 7.0)
            d.line([p0, pm, p1], fill=COL_THATCH_MID, width=5)
            d.line([p0, pm, p1], fill=COL_INK, width=1)

    im_1x = im.resize((336, 196), Image.Resampling.LANCZOS)
    return _add_paper_weathering(im_1x, seed=406, strength=5.5)


def build_cave_gnarled_roots() -> np.ndarray:
    """284x264 giant gnarled ancient roots & mossy cavern crag (盘根古木, aligned to master_b)."""
    S = 2
    W, H = 284 * S, 264 * S
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    d.ellipse([48, 436, 520, 522], fill=(12, 16, 16, 116))

    # Cavern crag boulder base anchored at bottom baseline
    rock_pts = [(74, 488), (118, 358), (264, 312), (434, 356), (496, 478), (358, 520), (168, 518)]
    d.polygon(rock_pts, fill=COL_STONE_DARK, outline=COL_INK)
    d.polygon([(118, 358), (264, 312), (376, 368), (218, 412)], fill=COL_STONE_MID, outline=COL_INK_SOFT)

    # Gnarled ancient primary & secondary root tendrils
    root_paths = [
        ([(246, 34), (232, 126), (186, 228), (124, 344), (62, 472)], 38, 14),
        ([(286, 26), (294, 134), (336, 242), (408, 362), (494, 486)], 40, 14),
        ([(266, 72), (262, 186), (242, 304), (212, 424), (176, 514)], 34, 12),
        ([(298, 96), (318, 214), (312, 336), (344, 438), (374, 516)], 30, 11),
        ([(224, 88), (168, 168), (108, 248), (68, 346), (44, 426)], 24, 9),
        ([(318, 78), (382, 158), (442, 248), (488, 344), (522, 424)], 24, 9),
    ]
    for pts, w_start, w_end in root_paths:
        segs = len(pts) - 1
        for si in range(segs):
            p0 = np.array(pts[si], dtype=np.float32)
            p1 = np.array(pts[si + 1], dtype=np.float32)
            for sub in range(8):
                t0 = sub / 8.0
                t1 = (sub + 1) / 8.0
                ga = (si + t0) / float(segs)
                rw = int(round(w_start * (1.0 - ga) + w_end * ga))
                qa = p0 * (1.0 - t0) + p1 * t0
                qb = p0 * (1.0 - t1) + p1 * t1
                d.line([tuple(qa), tuple(qb)], fill=COL_INK, width=rw + 6)
                d.line([tuple(qa), tuple(qb)], fill=(66, 52, 40, 255), width=rw)
                d.line(
                    [(qa[0] - rw * 0.18, qa[1] - 2), (qb[0] - rw * 0.18, qb[1] - 2)],
                    fill=(96, 78, 58, 255),
                    width=max(2, rw // 3),
                )

    # Moss cushions & subtle spirit-vein jade glints on root knots
    for mx, my, mrx, mry in [
        (188, 236, 26, 14),
        (328, 258, 28, 15),
        (238, 366, 32, 16),
        (378, 392, 26, 14),
        (124, 418, 24, 12),
    ]:
        d.ellipse([mx - mrx, my - mry, mx + mrx, my + mry], fill=COL_MOSS, outline=COL_INK_SOFT)
        d.ellipse([mx - mrx // 2, my - mry // 2, mx + mrx // 3, my + mry // 3], fill=(98, 134, 104, 220))

    im_1x = im.resize((284, 264), Image.Resampling.LANCZOS)
    return _add_paper_weathering(im_1x, seed=407, strength=6.0)


def build_cave_stone_steps() -> np.ndarray:
    """236x164 carved mossy stone stairs (古窟石阶) for underground cave elevation transitions."""
    S = 2
    W, H = 236 * S, 164 * S
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    d.polygon([(38, 214), (318, 92), (442, 198), (164, 322)], fill=(12, 16, 16, 118))

    # 5 stepped carved stone treads descending from top-right toward bottom-left
    n_steps = 5
    for i in range(n_steps - 1, -1, -1):
        # i=4 highest back step, i=0 lowest front step
        u = i / float(n_steps)
        sx = 74 + i * 48
        sy = 232 - i * 30
        tread = [
            (sx, sy),
            (sx + 62, sy - 26),
            (sx + 172, sy + 52),
            (sx + 110, sy + 78),
        ]
        riser = [
            (sx, sy),
            (sx + 110, sy + 78),
            (sx + 110, sy + 96),
            (sx, sy + 18),
        ]
        side_cheek = [
            (sx + 110, sy + 78),
            (sx + 172, sy + 52),
            (sx + 172, sy + 70),
            (sx + 110, sy + 96),
        ]
        d.polygon(tread, fill=COL_STONE_HI if i % 2 == 0 else COL_STONE_MID, outline=COL_INK)
        d.polygon(riser, fill=COL_STONE_DARK, outline=COL_INK)
        d.polygon(side_cheek, fill=COL_STONE_MID, outline=COL_INK)
        # Moss patches along step crevices
        mx = int(sx + 38 + (i % 3) * 22)
        my = int(sy + 26 + (i % 2) * 14)
        d.ellipse([mx - 16, my - 7, mx + 16, my + 7], fill=COL_MOSS)

    # Flanking carved stone cheek curbs (云雷纹抱鼓护石)
    for ox, oy in [(56, 214), (172, 294)]:
        curb_top = [(ox, oy), (ox + 252, oy - 122), (ox + 272, oy - 108), (ox + 20, oy + 14)]
        curb_side = [(ox + 20, oy + 14), (ox + 272, oy - 108), (ox + 272, oy - 86), (ox + 20, oy + 36)]
        d.polygon(curb_top, fill=COL_STONE_HI, outline=COL_INK)
        d.polygon(curb_side, fill=COL_STONE_DARK, outline=COL_INK)

    im_1x = im.resize((236, 164), Image.Resampling.LANCZOS)
    return _add_paper_weathering(im_1x, seed=408, strength=5.5)


def build_fg_bamboo_leaf() -> np.ndarray:
    """144x96 Song-Ming calligraphic wind-swept bamboo leaf cluster for Layer 3 foreground parallax."""
    S = 2
    W, H = 144 * S, 96 * S
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    # Slender bamboo twig
    d.line([(18, 26), (118, 56), (224, 96)], fill=(28, 40, 36, 230), width=4)

    leaves = [
        [(64, 40), (118, 18), (186, 14), (132, 38)],
        [(88, 48), (156, 52), (246, 76), (164, 68)],
        [(54, 42), (96, 82), (166, 134), (104, 96)],
        [(134, 64), (198, 48), (274, 54), (206, 72)],
        [(122, 62), (168, 108), (236, 166), (174, 124)],
    ]
    for lpts in leaves:
        d.polygon(lpts, fill=(32, 48, 42, 236), outline=(18, 26, 24, 245))
        d.line([lpts[0], lpts[2]], fill=(54, 76, 66, 210), width=2)

    # Soft depth-of-field blur for Layer 3 foreground lens feel
    im_blur = im.filter(ImageFilter.GaussianBlur(radius=1.6))
    im_1x = im_blur.resize((144, 96), Image.Resampling.LANCZOS)
    return clamp_song_ming_mineral_hsv(np.array(im_1x, dtype=np.uint8))


def build_light_radial_soft() -> np.ndarray:
    """256x256 smooth cosine-squared radial PointLight2D texture (0 fluorescent pixels, zero hard box edge)."""
    N = 256
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    cx = (N - 1) * 0.5
    cy = (N - 1) * 0.5
    r = np.sqrt(((xx - cx) / cx) ** 2 + ((yy - cy) / cy) ** 2)
    t = np.clip(1.0 - r, 0.0, 1.0)
    # Smooth C2 radial falloff: bright warm-neutral core, zero energy at r >= 1.0
    falloff = (t * t) * (3.0 - 2.0 * t) * t
    arr = np.zeros((N, N, 4), dtype=np.uint8)
    # Neutral warm-ivory RGB <= 232 so PointLight2D.color controls exact warm/cool tint and 0 neon pixels exist
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
            "tools/build_polish_r4_world.py (2x-supersampled Song-Ming 粉墙黛瓦 Jiangnan pitched-tile folk residence A aligned to master_a_tingyu_town.png)",
        ),
        "project/assets/world/prop_folk_house_b.png": (
            build_folk_house_b(),
            "world_prop",
            "tools/build_polish_r4_world.py (2x-supersampled Song-Ming 粉墙黛瓦 Jiangnan eave-veranda folk residence B with hanging paper lantern)",
        ),
        "project/assets/world/prop_yaolu_courtyard_wall.png": (
            build_yaolu_courtyard_wall(),
            "world_prop",
            "tools/build_polish_r4_world.py (2x-supersampled whitewashed courtyard wall segment with cut-bluestone dado & dark fish-scale tile coping)",
        ),
        "project/assets/world/prop_yaolu_gatehouse.png": (
            build_yaolu_gatehouse(),
            "world_prop",
            "tools/build_polish_r4_world.py (2x-supersampled timber & thatch courtyard gatehouse with canonical Simplified Chinese '济世药庐' plaque)",
        ),
        "project/assets/world/prop_yaolu_alchemy_pavilion.png": (
            build_yaolu_alchemy_pavilion(),
            "world_prop",
            "tools/build_polish_r4_world.py (2x-supersampled open-sided thatched alchemy pavilion on raised bluestone terrace aligned to master_a_tingyu_town.png)",
        ),
        "project/assets/world/prop_mountain_plank_bridge.png": (
            build_mountain_plank_bridge(),
            "world_prop",
            "tools/build_polish_r4_world.py (2x-supersampled wet cedar mountain plank bridge with hemp-bound timber guardrails for qinglan_pass)",
        ),
        "project/assets/world/prop_cave_gnarled_roots.png": (
            build_cave_gnarled_roots(),
            "world_prop",
            "tools/build_polish_r4_world.py (2x-supersampled giant gnarled ancient roots & mossy cavern crag aligned to master_b_cangmu_rtwp.png)",
        ),
        "project/assets/world/prop_cave_stone_steps.png": (
            build_cave_stone_steps(),
            "world_prop",
            "tools/build_polish_r4_world.py (2x-supersampled carved mossy underground cavern stone steps with cloud-fret cheek curbs)",
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

    raw_arrays: dict[str, np.ndarray] = {}
    meta_list: list[dict[str, str]] = []
    audit_rows: dict[str, Any] = {}

    for rel_p in sorted(generated.keys()):
        arr, cat, method = generated[rel_p]
        full_p = os.path.join(REPO_ROOT, rel_p)
        save_rgba_deterministic(arr, full_p)
        reloaded = np.array(Image.open(full_p).convert("RGBA"), dtype=np.uint8)
        neon_strict = count_fluorescent_pixels(reloaded, val_thresh=235, sat_thresh=0.85)
        neon_e2e = count_fluorescent_pixels(reloaded, val_thresh=245, sat_thresh=0.92)
        assert neon_strict == 0 and neon_e2e == 0, (
            f"Fluorescent pixel violation in {rel_p}: strict={neon_strict}, e2e={neon_e2e}"
        )
        raw_arrays[rel_p] = reloaded
        meta_list.append(
            {"path": rel_p, "category": cat, "creation_method": method}
        )
        audit_rows[rel_p] = {
            "dimensions": f"{reloaded.shape[1]}x{reloaded.shape[0]}",
            "sha256": sha256_file(full_p),
            "neon_strict_235_085": neon_strict,
            "neon_e2e_245_092": neon_e2e,
        }

    sheet_arr = build_provenance_contact_sheet(raw_arrays)
    sheet_full = os.path.join(REPO_ROOT, SOURCE_SHEET_REL)
    save_rgb_deterministic(sheet_arr, sheet_full)

    spec_doc = {
        "milestone": "M4_polish_r4_world_lighting",
        "generated_date": GEN_DATE,
        "source_contact_sheet": SOURCE_SHEET_REL,
        "source_contact_sheet_sha256": sha256_file(sheet_full),
        "assets": audit_rows,
    }
    spec_full = os.path.join(REPO_ROOT, SOURCE_SPEC_REL)
    os.makedirs(os.path.dirname(spec_full), exist_ok=True)
    with open(spec_full, "w", encoding="utf-8") as fh:
        json.dump(spec_doc, fh, ensure_ascii=False, indent=2, sort_keys=True)
        fh.write("\n")

    total_registered = update_asset_manifest(meta_list)
    print(
        f"Polish R4 World Build OK: {len(meta_list)} assets generated (0 fluorescent px), "
        f"{total_registered} total manifest entries verified."
    )


if __name__ == "__main__":
    build_all()
