#!/usr/bin/env python3
"""
Milestone M3 (Polish Round 3) Deterministic Song-Ming Gongbi UI Asset Builder.

Generates all 22 M3 imported UI frames & icons plus `assets_src/ui/r3_*` provenance
contact sheet and specification JSON, then updates `docs/asset-manifest.json` with
exact SHA-256 digests:
1. Carved Dark-Ebony Outer Casket Frame (`1920x1080`, lossy mode=1) & Open Thread-Bound
   Aged Xuan-Paper Tome Spread (`1704x856`, lossy mode=1) + Page-Flip Curling Leaf.
2. 2x-Supersampled Classical Brush-Ink Human Meridian Figure (`460x550`) + Glowing
   Celadon-Jade Bi-Disc Acupoints (`64x64`), Zero AI Gibberish Text.
3. Embossed Double-Bordered Artifact Slot Cards (`144x156` normal & selected),
   5 Monochrome Brush-Ink Empty-Slot Silhouettes (`96x96`), Bronze Potential Bar Trough/Fill,
   Active/Inactive Tab Plaques, and World `Alt` Xuan-Paper Nameplate.
4. Bronze Tripod Alchemy Cauldron Stage (`540x268`), 8-Frame Flickering Wen/Wu Hearth
   Flame Strip (`1024x220`), Engraved Ebony Fire Gauge (`860x54`), Phase Seal, & Jade Ripple.

Hygiene: Pure in-memory premultiplied float32 RGBA pipeline, fixed RNG seeds, constant
GEN_DATE, and strict Song-Ming mineral HSV clamp (`count_fluorescent_pixels == 0`).
"""

from __future__ import annotations

import hashlib
import json
import math
import os
from typing import Any

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GEN_DATE = "2026-11-27"
LICENSE_R3 = (
    "AI-Assisted & Procedural First-Party Original Asset "
    "(Song-Ming Gongbi Refinement, Commercial Rights Cleared)"
)
SOURCE_SHEET_REL = "assets_src/ui/r3_casket_alchemy_source.png"
SOURCE_SPEC_REL = "assets_src/ui/r3_casket_alchemy_spec.json"


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def clean_zero_alpha(arr: np.ndarray) -> np.ndarray:
    out = arr.copy()
    if out.ndim == 3 and out.shape[2] == 4:
        z = out[..., 3] == 0
        out[z, 0] = 0
        out[z, 1] = 0
        out[z, 2] = 0
    return out


def clamp_song_ming_mineral_hsv(arr: np.ndarray) -> np.ndarray:
    """Clamps peak saturation on high-value pixels so neon/fluorescent count is strictly 0."""
    out = arr.copy()
    rgb = out[..., :3].astype(np.float32)
    cmax = rgb.max(axis=-1)
    cmin = rgb.min(axis=-1)
    sat = np.where(cmax > 0.0, (cmax - cmin) / np.maximum(cmax, 1.0), 0.0)
    hot = (cmax > 220.0) & (sat > 0.76)
    if np.any(hot):
        target_s = np.minimum(sat, 0.76)
        scale = np.where(sat > 1e-5, target_s / np.maximum(sat, 1e-5), 1.0)
        rgb_new = cmax[..., None] - (cmax[..., None] - rgb) * scale[..., None]
        rgb = np.where(hot[..., None], np.minimum(rgb_new, 236.0), rgb)
    # Also cap ultra-saturated dark/mid pixels away from >=0.90 saturation
    high_sat = sat > 0.84
    if np.any(high_sat):
        scale2 = np.where(sat > 1e-5, 0.84 / np.maximum(sat, 1e-5), 1.0)
        rgb_new2 = cmax[..., None] - (cmax[..., None] - rgb) * scale2[..., None]
        rgb = np.where(high_sat[..., None], rgb_new2, rgb)
    out[..., :3] = np.clip(np.round(rgb), 0.0, 255.0).astype(np.uint8)
    return clean_zero_alpha(out)


def count_fluorescent_pixels(
    arr: np.ndarray, val_thresh: int = 235, sat_thresh: float = 0.85
) -> int:
    rgb = arr[..., :3].astype(np.float32)
    cmax = rgb.max(axis=-1)
    cmin = rgb.min(axis=-1)
    sat = np.where(cmax > 0.0, (cmax - cmin) / np.maximum(cmax, 1.0), 0.0)
    mask = (cmax >= float(val_thresh)) & (sat >= sat_thresh)
    if arr.shape[2] == 4:
        mask = mask & (arr[..., 3] > 0)
    return int(mask.sum())


def resize_premultiplied_rgba(
    rgba: np.ndarray, target_w: int, target_h: int
) -> np.ndarray:
    """Resizes uint8 RGBA in premultiplied float32 space with explicit [0,255] clipping."""
    src = rgba.astype(np.float32)
    a01 = src[..., 3:4] / 255.0
    pre = np.concatenate([src[..., :3] * a01, src[..., 3:4]], axis=2)
    interp = cv2.INTER_AREA if (target_w < rgba.shape[1]) else cv2.INTER_LANCZOS4
    resized_pre = cv2.resize(pre, (target_w, target_h), interpolation=interp)
    ra = np.clip(resized_pre[..., 3:4] / 255.0, 0.0, 1.0)
    rgb = np.where(
        ra > 1e-4,
        np.clip(resized_pre[..., :3] / np.maximum(ra, 1e-5), 0.0, 255.0),
        0.0,
    )
    out = np.concatenate(
        [np.round(rgb), np.round(ra * 255.0)], axis=2
    ).astype(np.uint8)
    return clamp_song_ming_mineral_hsv(out)


def alpha_over_np(dst: np.ndarray, src: np.ndarray) -> None:
    sa = src[..., 3:4].astype(np.float32) / 255.0
    if not np.any(sa > 0.0):
        return
    da = dst[..., 3:4].astype(np.float32) / 255.0
    out_a = sa + da * (1.0 - sa)
    safe_a = np.maximum(out_a, 1e-6)
    sc = src[..., :3].astype(np.float32)
    dc = dst[..., :3].astype(np.float32)
    out_c = (sc * sa + dc * da * (1.0 - sa)) / safe_a
    dst[..., :3] = np.where(
        out_a > 1e-4, np.clip(np.round(out_c), 0.0, 255.0), 0.0
    ).astype(np.uint8)
    dst[..., 3:4] = np.clip(np.round(out_a * 255.0), 0.0, 255.0).astype(np.uint8)


def save_rgba_deterministic(arr: np.ndarray, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    clamped = clamp_song_ming_mineral_hsv(arr)
    Image.fromarray(clamped, mode="RGBA").save(path, format="PNG", compress_level=9)


def save_rgb_deterministic(arr: np.ndarray, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    clamped = clamp_song_ming_mineral_hsv(arr)
    Image.fromarray(clamped[..., :3], mode="RGB").save(
        path, format="PNG", compress_level=9
    )


def _draw_ruyi_corner(
    draw: ImageDraw.ImageDraw,
    cx: float,
    cy: float,
    sx: float,
    sy: float,
    scale: float,
    col_hi: tuple[int, int, int, int],
    col_sh: tuple[int, int, int, int],
) -> None:
    """Draws symmetrical carved Ruyi cloud-scroll relief ornament in a corner."""
    arms = [
        [(0, 0), (26, 4), (48, 14), (62, 28), (52, 38), (36, 32)],
        [(0, 0), (4, 26), (14, 48), (28, 62), (38, 52), (32, 36)],
    ]
    for arm in arms:
        pts_sh = [
            (cx + sx * p[0] * scale + 2.0, cy + sy * p[1] * scale + 2.0) for p in arm
        ]
        pts_hi = [(cx + sx * p[0] * scale, cy + sy * p[1] * scale) for p in arm]
        draw.line(pts_sh, fill=col_sh, width=max(2, int(round(4.5 * scale))))
        draw.line(pts_hi, fill=col_hi, width=max(1, int(round(2.8 * scale))))
    # Spiral Ruyi head
    for r_i, col in [(16 * scale, col_sh), (13 * scale, col_hi)]:
        rx = cx + sx * 22 * scale
        ry = cy + sy * 22 * scale
        draw.arc(
            [rx - r_i, ry - r_i, rx + r_i, ry + r_i],
            start=0,
            end=300,
            fill=col,
            width=max(1, int(round(2.4 * scale))),
        )


# ==============================================================================
# 1. Carved Dark-Ebony Outer Casket Frame (1920x1080)
# ==============================================================================
def build_casket_ebony_outer_frame() -> np.ndarray:
    w, h = 1920, 1080
    rng = np.random.default_rng(20261131)

    # Base dark carved ebony woodgrain (#161310 .. #211C17) -> luma ~0.095 << 0.17
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    grain_h = np.sin(yy * 0.19 + np.sin(xx * 0.014) * 2.4) * 3.2
    grain_v = np.sin(xx * 0.17 + np.cos(yy * 0.016) * 2.1) * 2.6
    fine_noise = rng.normal(0.0, 1.4, size=(h, w)).astype(np.float32)

    edge_mask = (xx < 96) | (xx > w - 96) | (yy < 136) | (yy > h - 68)
    grain = np.where((xx < 96) | (xx > w - 96), grain_v, grain_h) + fine_noise

    base = np.zeros((h, w, 4), dtype=np.uint8)
    r = np.clip(23.0 + grain * 0.9, 12.0, 38.0)
    g = np.clip(19.5 + grain * 0.8, 10.0, 33.0)
    b = np.clip(16.5 + grain * 0.7, 9.0, 29.0)
    base[..., 0] = r.astype(np.uint8)
    base[..., 1] = g.astype(np.uint8)
    base[..., 2] = b.astype(np.uint8)
    base[..., 3] = 255

    # Deep recessed book well (x: 92..1828, y: 138..1024)
    well = (xx >= 92) & (xx <= 1828) & (yy >= 138) & (yy <= 1024)
    base[well, 0] = np.clip(15.0 + fine_noise[well] * 0.6, 10.0, 22.0).astype(np.uint8)
    base[well, 1] = np.clip(13.0 + fine_noise[well] * 0.5, 9.0, 19.0).astype(np.uint8)
    base[well, 2] = np.clip(12.0 + fine_noise[well] * 0.5, 8.0, 18.0).astype(np.uint8)
    _ = edge_mask

    im = Image.fromarray(base, mode="RGBA")
    draw = ImageDraw.Draw(im, "RGBA")

    # Outer & inner carved moldings
    draw.rectangle([4, 4, w - 5, h - 5], outline=(58, 47, 34, 255), width=3)
    draw.rectangle([12, 12, w - 13, h - 13], outline=(14, 11, 9, 255), width=4)
    draw.rectangle([20, 20, w - 21, h - 21], outline=(46, 38, 28, 235), width=2)

    # Top header recessed trough (y: 24..114, x: 176..1804)
    draw.rounded_rectangle(
        [176, 22, 1804, 114],
        radius=6,
        fill=(18, 15, 13, 248),
        outline=(74, 59, 41, 220),
        width=2,
    )
    draw.line([180, 113, 1800, 113], fill=(92, 74, 48, 165), width=1)

    # Book well mitered ebony-bronze frame (x: 86..1834, y: 132..1030)
    draw.rectangle([84, 130, 1836, 1032], outline=(11, 9, 8, 255), width=5)
    draw.rectangle([89, 135, 1831, 1027], outline=(86, 68, 44, 235), width=2)
    draw.rectangle([93, 139, 1827, 1023], outline=(36, 29, 21, 255), width=2)

    # Subtle carved Ruyi corner reliefs (kept dark carved wood so corner luma < 0.12)
    wood_hi = (52, 43, 32, 225)
    wood_sh = (10, 8, 7, 235)
    _draw_ruyi_corner(draw, 26, 26, 1, 1, 1.15, wood_hi, wood_sh)
    _draw_ruyi_corner(draw, w - 26, 26, -1, 1, 1.15, wood_hi, wood_sh)
    _draw_ruyi_corner(draw, 26, h - 26, 1, -1, 1.15, wood_hi, wood_sh)
    _draw_ruyi_corner(draw, w - 26, h - 26, -1, -1, 1.15, wood_hi, wood_sh)

    # Side vertical carved panel grooves
    for sx0, sx1 in [(32, 68), (w - 68, w - 32)]:
        draw.rounded_rectangle(
            [sx0, 168, sx1, 996],
            radius=8,
            outline=(44, 36, 27, 210),
            width=2,
        )
        for ky in range(230, 960, 120):
            draw.ellipse(
                [sx0 + 8, ky - 14, sx1 - 8, ky + 14],
                outline=(50, 41, 30, 185),
                width=2,
            )

    return clamp_song_ming_mineral_hsv(np.array(im, dtype=np.uint8))


# ==============================================================================
# 2. Open Thread-Bound Aged Xuan-Paper Tome Spread (1704x856) + Page Flip Leaf
# ==============================================================================
def build_casket_xuan_tome_spread() -> np.ndarray:
    w, h = 1704, 856
    rng = np.random.default_rng(20261132)

    arr = np.zeros((h, w, 4), dtype=np.uint8)
    im = Image.fromarray(arr, mode="RGBA")
    draw = ImageDraw.Draw(im, "RGBA")

    # Outer indigo-ebony cloth book-board cover lip
    draw.rounded_rectangle(
        [0, 0, w - 1, h - 1],
        radius=6,
        fill=(32, 30, 28, 255),
        outline=(84, 69, 48, 255),
        width=2,
    )
    draw.rounded_rectangle(
        [4, 4, w - 5, h - 5],
        radius=4,
        fill=(44, 41, 38, 255),
        outline=(22, 19, 16, 255),
        width=2,
    )

    # Stacked stepped deckle Xuan-paper pages (6 visible page thickness steps on L/R/Bottom)
    for step in range(6):
        inset_x = 8 + step * 3
        inset_top = 7 + step * 1
        inset_bot = h - 8 - (5 - step) * 2
        shade = 166 + step * 9
        col = (
            min(224, shade + 10),
            min(214, shade + 2),
            min(195, shade - 12),
            255,
        )
        draw.rectangle(
            [inset_x, inset_top, w - 1 - inset_x, inset_bot],
            fill=col,
            outline=(112, 97, 76, 210),
            width=1,
        )

    base = np.array(im, dtype=np.uint8)

    # Main open aged Xuan-paper interior (x: 26..1678, y: 12..838)
    px0, px1, py0, py1 = 26, w - 26, 12, h - 18
    pw, ph = px1 - px0, py1 - py0
    yy, xx = np.mgrid[0:ph, 0:pw].astype(np.float32)

    # Laid Xuan-paper horizontal bamboo-screen lines + organic tea-aged cloudiness
    low_cloud = cv2.GaussianBlur(
        rng.normal(0.0, 1.0, size=(ph // 8 + 2, pw // 8 + 2)).astype(np.float32),
        (9, 9),
        2.2,
    )
    low_cloud = cv2.resize(low_cloud, (pw, ph), interpolation=cv2.INTER_CUBIC)
    laid_lines = np.sin(yy * 1.45) * 1.15 + np.sin(xx * 0.28 + yy * 0.07) * 0.85
    fiber = rng.normal(0.0, 1.6, size=(ph, pw)).astype(np.float32)

    # Gentle edge age vignette (keeps interior bright ~0.76 luma, R > G > B)
    nx = (xx / float(pw)) * 2.0 - 1.0
    ny = (yy / float(ph)) * 2.0 - 1.0
    edge_dist = np.maximum(np.abs(nx) ** 3.2, np.abs(ny) ** 3.0)
    vig = edge_dist * 18.0

    # Warm Song-Ming aged Xuan paper (#D8CBB4 -> #E1D7C4): R=221, G=210, B=189
    pr = np.clip(221.0 + low_cloud * 6.5 + laid_lines + fiber - vig * 0.90, 182.0, 236.0)
    pg = np.clip(210.0 + low_cloud * 6.0 + laid_lines + fiber - vig * 1.00, 170.0, 226.0)
    pb = np.clip(189.0 + low_cloud * 5.2 + laid_lines + fiber - vig * 1.15, 146.0, 208.0)

    base[py0:py1, px0:px1, 0] = pr.astype(np.uint8)
    base[py0:py1, px0:px1, 1] = pg.astype(np.uint8)
    base[py0:py1, px0:px1, 2] = pb.astype(np.uint8)
    base[py0:py1, px0:px1, 3] = 255

    # Subtle outer border shadow inside paper sheet
    im2 = Image.fromarray(base, mode="RGBA")
    d2 = ImageDraw.Draw(im2, "RGBA")
    d2.rectangle([px0, py0, px1 - 1, py1 - 1], outline=(136, 118, 92, 220), width=2)
    d2.rectangle([px0 + 3, py0 + 3, px1 - 4, py1 - 4], outline=(176, 160, 134, 140), width=1)

    # Thread-bound silk binding stitches along far-left edge (traditional线装古籍装订线)
    stitch_x = px0 + 8
    d2.line([stitch_x, py0 + 18, stitch_x, py1 - 18], fill=(96, 82, 64, 145), width=2)
    for sy in [110, 295, 480, 665]:
        d2.line([px0, sy, stitch_x + 5, sy], fill=(108, 92, 72, 175), width=2)
        d2.ellipse(
            [stitch_x - 2, sy - 3, stitch_x + 3, sy + 3],
            fill=(74, 60, 46, 190),
        )

    return clamp_song_ming_mineral_hsv(np.array(im2, dtype=np.uint8))


def build_casket_page_flip_leaf() -> np.ndarray:
    w, h = 600, 856
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    t = xx / float(max(1, w - 1))
    # Curling Xuan page highlight + soft cast shadow along leading edge
    arch = np.sin(t * math.pi)
    r = np.clip(208.0 + arch * 24.0, 160.0, 234.0)
    g = np.clip(197.0 + arch * 22.0, 150.0, 224.0)
    b = np.clip(176.0 + arch * 19.0, 132.0, 204.0)
    alpha = np.where(
        (yy >= 14) & (yy <= h - 18),
        np.clip(np.sin(t * math.pi) * 215.0, 0.0, 215.0),
        0.0,
    )
    out = np.stack([r, g, b, alpha], axis=-1).astype(np.uint8)
    return clamp_song_ming_mineral_hsv(out)


# ==============================================================================
# 3. Classical Brush-Ink Meridian Figure (460x550) & Celadon-Jade Acupoint (64x64)
# ==============================================================================
def _stamp_jade_bi_disc(
    draw: ImageDraw.ImageDraw,
    cx: float,
    cy: float,
    outer_r: float,
    gold_rim: bool = False,
) -> None:
    """Draws a glowing Song-Ming celadon-jade circular bi-disc (玉璧穴位环)."""
    # Soft outer celadon aura
    for step in range(5, 0, -1):
        rr = outer_r + step * 3.2
        a = int(16 * (6 - step))
        draw.ellipse(
            [cx - rr, cy - rr, cx + rr, cy + rr],
            fill=(78, 168, 138, a),
        )
    # Main celadon-jade disc (#46987B .. #66B89A: G >> R, 0 neon)
    draw.ellipse(
        [cx - outer_r, cy - outer_r, cx + outer_r, cy + outer_r],
        fill=(74, 156, 128, 248),
        outline=(42, 96, 78, 255),
        width=max(2, int(round(outer_r * 0.13))),
    )
    mid_r = outer_r * 0.72
    draw.ellipse(
        [cx - mid_r, cy - mid_r, cx + mid_r, cy + mid_r],
        fill=(98, 182, 152, 245),
        outline=(142, 208, 182, 215),
        width=max(1, int(round(outer_r * 0.09))),
    )
    if gold_rim:
        gr = outer_r + 2.0
        draw.ellipse(
            [cx - gr, cy - gr, cx + gr, cy + gr],
            outline=(198, 156, 82, 210),
            width=max(2, int(round(outer_r * 0.10))),
        )
    # Central bi-disc hole
    hole_r = max(3.0, outer_r * 0.27)
    draw.ellipse(
        [cx - hole_r, cy - hole_r, cx + hole_r, cy + hole_r],
        fill=(62, 52, 38, 235),
        outline=(188, 162, 112, 220),
        width=max(1, int(round(outer_r * 0.08))),
    )


def build_casket_acupoint_jade() -> np.ndarray:
    ss = 128
    im = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im, "RGBA")
    _stamp_jade_bi_disc(draw, 64.0, 64.0, 38.0, gold_rim=True)
    return resize_premultiplied_rgba(np.array(im, dtype=np.uint8), 64, 64)


def build_casket_meridian_figure() -> np.ndarray:
    """2x-supersampled (920x1100 -> 460x550) classical brush-ink human meridian figure."""
    sw, sh = 920, 1100
    cx = 448.0  # Aligned with global x ~ 410 when placed on Left Page!
    im = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im, "RGBA")

    ink_main = (34, 28, 23, 248)
    ink_fine = (62, 51, 41, 212)
    ink_wash = (214, 202, 180, 38)   # Delicate Xuan-harmonized pale brush wash
    ink_shade = (128, 112, 92, 68)   # Classical Gongbi anatomical contour wash
    channel_sepia = (68, 54, 40, 212)
    channel_jade = (64, 150, 120, 218)

    # 1. Symmetrical front-standing meditative cultivator silhouette (graceful curved contours)
    torso_poly = [
        (cx - 32, 236),   # left neck base
        (cx - 68, 256),   # left trapezius slope
        (cx - 138, 282),  # left shoulder cap
        (cx - 154, 322),  # left deltoid outer
        (cx - 118, 418),  # left armpit
        (cx - 108, 504),  # left ribcage
        (cx - 98, 586),   # left waist taper
        (cx - 114, 704),  # left iliac/hip curve
        (cx - 108, 964),  # left outer thigh
        (cx - 42, 964),   # left inner thigh
        (cx - 14, 804),   # perineum/groin
        (cx + 14, 804),
        (cx + 42, 964),
        (cx + 108, 964),
        (cx + 114, 704),
        (cx + 98, 586),
        (cx + 108, 504),
        (cx + 118, 418),
        (cx + 154, 322),
        (cx + 138, 282),
        (cx + 68, 256),
        (cx + 32, 236),
    ]
    draw.polygon(torso_poly, fill=ink_wash)
    # Lateral rib/hip contour wash (matching master_d ink shading along flanks)
    for side in (-1.0, 1.0):
        flank_wash = [
            (cx + side * 116, 418),
            (cx + side * 98, 586),
            (cx + side * 112, 704),
            (cx + side * 106, 930),
            (cx + side * 88, 930),
            (cx + side * 94, 704),
            (cx + side * 82, 586),
            (cx + side * 100, 418),
        ]
        draw.polygon(flank_wash, fill=ink_shade)

    # Left & Right arms extending down-outward with open palms & 5 articulated fingers (master_d!)
    for side in (-1.0, 1.0):
        arm_poly = [
            (cx + side * 138, 284),
            (cx + side * 166, 334),
            (cx + side * 198, 492),
            (cx + side * 246, 656),
            (cx + side * 278, 738),  # radial wrist
            (cx + side * 326, 764),  # thumb tip
            (cx + side * 322, 780),
            (cx + side * 294, 778),  # thumb web
            (cx + side * 336, 858),  # index tip
            (cx + side * 322, 868),
            (cx + side * 302, 808),
            (cx + side * 316, 888),  # middle tip
            (cx + side * 300, 892),
            (cx + side * 284, 814),
            (cx + side * 292, 886),  # ring tip
            (cx + side * 276, 886),
            (cx + side * 266, 814),
            (cx + side * 268, 866),  # pinky tip
            (cx + side * 254, 862),
            (cx + side * 240, 770),  # ulnar wrist
            (cx + side * 196, 668),
            (cx + side * 150, 518),
            (cx + side * 118, 416),
        ]
        draw.polygon(arm_poly, fill=ink_wash)
        shade_strip = [
            (cx + side * 120, 416),
            (cx + side * 150, 518),
            (cx + side * 196, 668),
            (cx + side * 240, 768),
            (cx + side * 252, 760),
            (cx + side * 210, 658),
            (cx + side * 164, 508),
            (cx + side * 134, 408),
        ]
        draw.polygon(shade_strip, fill=ink_shade)
        draw.line(arm_poly + [arm_poly[0]], fill=ink_main, width=4, joint="curve")

    # Neck & Head (serene Song-Ming face matching master_d: short meditative hair/crown, clear eyes/nose/mouth)
    draw.polygon(
        [(cx - 34, 206), (cx + 34, 206), (cx + 38, 250), (cx - 38, 250)],
        fill=ink_wash,
    )
    for side in (-1.0, 1.0):
        draw.line([(cx + side * 33, 210), (cx + side * 35, 248)], fill=ink_main, width=4)
        # Sternocleidomastoid subtle tendon lines
        draw.line([(cx + side * 24, 216), (cx + side * 10, 262)], fill=ink_fine, width=2)

    # Hair crown & Cranium
    draw.ellipse([cx - 58, 72, cx + 58, 152], fill=(48, 40, 33, 225), outline=ink_main, width=4)
    head_pts = [
        (cx, 88),
        (cx - 48, 96),
        (cx - 60, 134),
        (cx - 56, 184),
        (cx - 38, 218),
        (cx, 232),
        (cx + 38, 218),
        (cx + 56, 184),
        (cx + 60, 134),
        (cx + 48, 96),
        (cx, 88),
    ]
    draw.polygon(head_pts[:-1], fill=(224, 213, 194, 165))
    draw.line(head_pts, fill=ink_main, width=4, joint="curve")
    # Ears
    for side in (-1.0, 1.0):
        ex = cx + side * 60
        draw.arc(
            [ex - 11, 140, ex + 11, 188],
            start=90 if side < 0 else -90,
            end=270 if side < 0 else 90,
            fill=ink_main,
            width=4,
        )
    # Serene meditative eyebrows, closed eyelids, nose bridge, and calm lips (100% unobstructed!)
    for side in (-1.0, 1.0):
        draw.arc(
            [cx + side * 26 - 18, 136, cx + side * 26 + 18, 152],
            start=195,
            end=345,
            fill=ink_main,
            width=3,
        )
        draw.arc(
            [cx + side * 26 - 15, 152, cx + side * 26 + 15, 164],
            start=15,
            end=165,
            fill=ink_main,
            width=3,
        )
    draw.line([(cx, 150), (cx, 184)], fill=ink_fine, width=3)
    draw.arc([cx - 9, 178, cx + 9, 190], start=10, end=170, fill=ink_fine, width=3)
    draw.line([(cx - 14, 204), (cx + 14, 204)], fill=ink_main, width=3)

    # Torso outer & anatomical clavicle / pectoral / rib strokes
    draw.line(torso_poly[:10], fill=ink_main, width=5, joint="curve")
    draw.line(torso_poly[9:13], fill=ink_main, width=5, joint="curve")
    draw.line(torso_poly[12:], fill=ink_main, width=5, joint="curve")
    for side in (-1.0, 1.0):
        draw.line([(cx + side * 14, 270), (cx + side * 116, 286)], fill=ink_fine, width=3)
        draw.arc(
            [cx + (side * 60) - 50, 332, cx + (side * 60) + 50, 408],
            start=15,
            end=165,
            fill=ink_fine,
            width=3,
        )
        draw.arc(
            [cx + (side * 48) - 36, 462, cx + (side * 48) + 36, 566],
            start=110 if side > 0 else 20,
            end=160 if side > 0 else 70,
            fill=ink_fine,
            width=2,
        )

    # 2. Twelve Regular Meridians & Eight Extraordinary Vessels (奇经八脉)
    draw.line([(cx, 66), (cx, 134)], fill=channel_jade, width=4)
    draw.line([(cx, 232), (cx, 768)], fill=channel_jade, width=5)
    draw.line([(cx, 232), (cx, 768)], fill=ink_main, width=2)

    for side in (-1.0, 1.0):
        pts_torso_m = [
            (cx + side * 26, 252),
            (cx + side * 46, 344),
            (cx + side * 44, 492),
            (cx + side * 40, 632),
            (cx + side * 28, 746),
            (cx + side * 66, 934),
        ]
        draw.line(pts_torso_m, fill=channel_sepia, width=3, joint="curve")
        pts_outer_m = [
            (cx + side * 88, 290),
            (cx + side * 94, 396),
            (cx + side * 82, 552),
            (cx + side * 86, 706),
            (cx + side * 86, 932),
        ]
        draw.line(pts_outer_m, fill=channel_sepia, width=2, joint="curve")
        pts_arm_m = [
            (cx, 444),
            (cx + side * 88, 308),
            (cx + side * 144, 348),
            (cx + side * 182, 508),
            (cx + side * 224, 658),
            (cx + side * 266, 768),
        ]
        draw.line(pts_arm_m, fill=channel_jade, width=4, joint="curve")
        draw.line(pts_arm_m, fill=channel_sepia, width=2, joint="curve")

        for mx, my in [
            (cx + side * 46, 344),
            (cx + side * 94, 396),
            (cx + side * 44, 524),
            (cx + side * 182, 508),
            (cx + side * 224, 658),
        ]:
            draw.ellipse(
                [mx - 7, my - 7, mx + 7, my + 7],
                fill=(196, 158, 86, 235),
                outline=ink_main,
                width=2,
            )

    # 3. Glowing Celadon-Jade Bi-Disc Acupoints (玉璧穴位环, matching master_d!)
    # Delicate brow Niwan node (so facial features stay crisp & expressive!)
    draw.ellipse([cx - 16, 120, cx + 16, 152], fill=(82, 168, 138, 85))
    draw.ellipse(
        [cx - 9, 127, cx + 9, 145],
        fill=(86, 174, 144, 245),
        outline=(198, 160, 88, 235),
        width=2,
    )

    acupoints = [
        (cx, 66.0, 25.0, True),            # 百会 (Crown above hairline, matching master_d!)
        (cx, 444.0, 32.0, False),          # 膻中 (Chest)
        (cx, 566.0, 24.0, False),          # 中脘 (Solar Plexus)
        (cx, 668.0, 35.0, True),           # 气海 (Qi Sea)
        (cx, 766.0, 38.0, True),           # 丹田 (Lower Dantian)
        (cx - 266.0, 768.0, 22.0, False),  # 左劳宫 (Left Palm)
        (cx + 266.0, 768.0, 22.0, False),  # 右劳宫 (Right Palm)
    ]
    for ax, ay, ar, grim in acupoints:
        _stamp_jade_bi_disc(draw, ax, ay, ar, gold_rim=grim)

    arr = np.array(im, dtype=np.uint8)
    for y in range(865, 975):
        fade = max(0.0, 1.0 - (y - 865) / 100.0)
        arr[y, :, 3] = np.round(arr[y, :, 3].astype(np.float32) * fade).astype(np.uint8)

    return resize_premultiplied_rgba(arr, 460, 550)


# ==============================================================================
# 4. Embossed 3+2 Artifact Slot Cards, Potential Bars, Tabs, Nameplates & Icons
# ==============================================================================
def build_casket_slot_card(selected: bool) -> np.ndarray:
    """2x-supersampled (288x312 -> 144x156) double-bordered embossed artifact slot."""
    sw, sh = 288, 312
    im = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im, "RGBA")

    pad = 16
    if selected:
        # Warm antique-gilt aura (non-fluorescent sat < 0.55)
        for step in range(7, 0, -1):
            rr = pad - step * 2
            a = int(20 * (8 - step))
            draw.rounded_rectangle(
                [rr, rr, sw - 1 - rr, sh - 1 - rr],
                radius=14,
                fill=(218, 182, 108, a),
            )

    # Outer carved antique-bronze border
    outer_border = (212, 174, 98, 255) if selected else (96, 78, 54, 255)
    inner_border = (232, 200, 132, 255) if selected else (172, 142, 92, 245)
    well_bg = (186, 173, 148, 255) if selected else (174, 161, 138, 255)
    plate_bg = (96, 78, 58, 255) if selected else (86, 71, 54, 255)

    draw.rounded_rectangle(
        [pad, pad, sw - 1 - pad, sh - 1 - pad],
        radius=10,
        fill=well_bg,
        outline=outer_border,
        width=5,
    )
    # Inner chamfered border
    draw.rounded_rectangle(
        [pad + 8, pad + 8, sw - 1 - pad - 8, sh - 1 - pad - 8],
        radius=6,
        outline=inner_border,
        width=3,
    )
    # Bottom bronze-taupe nameplate strip inside slot (matching master_d!)
    plate_y0 = sh - pad - 62
    draw.rounded_rectangle(
        [pad + 9, plate_y0, sw - 1 - pad - 9, sh - 1 - pad - 9],
        radius=4,
        fill=plate_bg,
    )
    draw.line(
        [pad + 9, plate_y0, sw - 1 - pad - 9, plate_y0],
        fill=inner_border,
        width=3,
    )

    # Corner cloud-scroll filigree inside icon well
    c_col = (122, 100, 68, 185)
    for cx0, cy0, sx, sy in [
        (pad + 14, pad + 14, 1, 1),
        (sw - pad - 14, pad + 14, -1, 1),
        (pad + 14, plate_y0 - 8, 1, -1),
        (sw - pad - 14, plate_y0 - 8, -1, -1),
    ]:
        draw.line([(cx0, cy0), (cx0 + sx * 22, cy0)], fill=c_col, width=2)
        draw.line([(cx0, cy0), (cx0, cy0 + sy * 22)], fill=c_col, width=2)
        draw.arc(
            [
                min(cx0, cx0 + sx * 14) - 4,
                min(cy0, cy0 + sy * 14) - 4,
                max(cx0, cx0 + sx * 14) + 4,
                max(cy0, cy0 + sy * 14) + 4,
            ],
            start=0,
            end=270,
            fill=c_col,
            width=2,
        )

    return resize_premultiplied_rgba(np.array(im, dtype=np.uint8), 144, 156)


def build_slot_silhouette(slot_kind: str) -> np.ndarray:
    """2x-supersampled (192x192 -> 96x96) Song-Ming monochrome brush-ink silhouette."""
    ss = 192
    im = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im, "RGBA")

    ink_dark = (46, 39, 32, 232)
    ink_mid = (72, 61, 50, 205)
    ink_light = (196, 184, 162, 215)

    if slot_kind == "weapon":
        # Diagonal ancient Daoist sword (matching master_d slot 1)
        blade = [(154, 30), (164, 40), (74, 130), (62, 118)]
        draw.polygon(blade, fill=ink_mid, outline=ink_dark, width=4)
        draw.line([(157, 35), (69, 123)], fill=ink_light, width=2)
        # Guard (剑格)
        guard = [(50, 104), (88, 142), (80, 150), (42, 112)]
        draw.polygon(guard, fill=ink_dark)
        # Hilt & pommel
        draw.line([(61, 131), (36, 156)], fill=ink_dark, width=10)
        draw.ellipse([24, 150, 44, 170], fill=ink_dark, outline=ink_light, width=2)

    elif slot_kind == "robe":
        # Wide-sleeved cross-collar Daoist robe (交领广袖法衣, matching master_d slot 2)
        robe_poly = [
            (72, 34),
            (120, 34),
            (168, 76),
            (150, 108),
            (126, 90),
            (136, 162),
            (56, 162),
            (66, 90),
            (42, 108),
            (24, 76),
        ]
        draw.polygon(robe_poly, fill=ink_dark)
        # Cross-collar y-lapel & waist sash in crisp light Xuan negative-space lines
        draw.line([(74, 36), (112, 98)], fill=ink_light, width=4)
        draw.line([(118, 36), (86, 82)], fill=ink_light, width=4)
        draw.rectangle([63, 98, 129, 112], fill=ink_mid, outline=ink_light, width=3)
        draw.line([(96, 112), (90, 158)], fill=ink_light, width=3)
        draw.line([(104, 112), (110, 156)], fill=ink_light, width=2)

    elif slot_kind == "boots":
        # Pair of cloud-scroll Daoist boots (云纹履腕, matching master_d slot 3)
        for ox, oy, scale_b in [(-20, -6, 0.92), (16, 6, 1.0)]:
            bx, by = 92 + ox, 96 + oy
            boot = [
                (bx - 16 * scale_b, by - 52 * scale_b),
                (bx + 20 * scale_b, by - 52 * scale_b),
                (bx + 18 * scale_b, by + 18 * scale_b),
                (bx + 26 * scale_b, by + 40 * scale_b),
                (bx - 36 * scale_b, by + 40 * scale_b),
                (bx - 42 * scale_b, by + 26 * scale_b),
                (bx - 18 * scale_b, by + 14 * scale_b),
            ]
            draw.polygon(boot, fill=ink_dark, outline=ink_light, width=2)
            # Thick white-felt sole & cloud cuff
            draw.line(
                [
                    (bx - 38 * scale_b, by + 35 * scale_b),
                    (bx + 24 * scale_b, by + 35 * scale_b),
                ],
                fill=ink_light,
                width=4,
            )
            draw.line(
                [
                    (bx - 14 * scale_b, by - 42 * scale_b),
                    (bx + 18 * scale_b, by - 42 * scale_b),
                ],
                fill=ink_light,
                width=3,
            )

    elif slot_kind == "pendant":
        # Circular jade bi-pendant with braided silk cord (玉璧灵佩, matching master_d slot 4)
        draw.arc([82, 18, 136, 76], start=120, end=330, fill=ink_dark, width=5)
        draw.arc([74, 24, 116, 78], start=180, end=360, fill=ink_dark, width=4)
        draw.ellipse([50, 62, 142, 154], fill=ink_mid, outline=ink_dark, width=5)
        draw.ellipse([64, 76, 128, 140], outline=ink_light, width=3)
        draw.ellipse([82, 94, 110, 122], fill=(0, 0, 0, 0), outline=ink_dark, width=4)
        # Punch transparent center hole
        arr_p = np.array(im, dtype=np.uint8)
        yy, xx = np.mgrid[0:ss, 0:ss]
        hole = (xx - 96) ** 2 + (yy - 108) ** 2 <= 12 ** 2
        arr_p[hole] = 0
        return resize_premultiplied_rgba(arr_p, 96, 96)

    else:
        # Isometric carved sword casket (本命剑匣, matching master_d slot 5)
        top_face = [(126, 46), (166, 68), (68, 134), (28, 112)]
        front_left = [(28, 112), (68, 134), (68, 156), (28, 134)]
        front_right = [(68, 134), (166, 68), (166, 90), (68, 156)]
        draw.polygon(top_face, fill=ink_mid, outline=ink_dark, width=4)
        draw.polygon(front_left, fill=ink_dark, outline=ink_light, width=2)
        draw.polygon(front_right, fill=ink_dark, outline=ink_light, width=2)
        # Lid seam & bronze clasp
        draw.line([(124, 54), (36, 113)], fill=ink_light, width=2)
        draw.line([(156, 70), (68, 129)], fill=ink_light, width=2)
        draw.polygon([(92, 86), (108, 95), (98, 103), (82, 94)], fill=ink_light)

    return resize_premultiplied_rgba(np.array(im, dtype=np.uint8), 96, 96)


def build_casket_potential_bar_bg() -> np.ndarray:
    w, h = 260, 26
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im, "RGBA")
    pts = [
        (10, 2),
        (w - 11, 2),
        (w - 2, h // 2),
        (w - 11, h - 3),
        (10, h - 3),
        (2, h // 2),
    ]
    draw.polygon(pts, fill=(44, 37, 29, 250), outline=(118, 94, 58, 255), width=2)
    pts_in = [
        (12, 5),
        (w - 13, 5),
        (w - 6, h // 2),
        (w - 13, h - 6),
        (12, h - 6),
        (6, h // 2),
    ]
    draw.polygon(pts_in, fill=(35, 29, 23, 255), outline=(72, 58, 38, 220), width=1)
    return clamp_song_ming_mineral_hsv(np.array(im, dtype=np.uint8))


def build_casket_potential_bar_fill() -> np.ndarray:
    w, h = 252, 18
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    bevel = 1.0 - np.abs((yy / float(max(1, h - 1))) * 2.0 - 1.0) * 0.28
    shimmer = 1.0 + 0.06 * np.sin(xx * 0.06)
    r = np.clip(186.0 * bevel * shimmer, 120.0, 218.0)
    g = np.clip(148.0 * bevel * shimmer, 94.0, 178.0)
    b = np.clip(78.0 * bevel * shimmer, 48.0, 102.0)
    a = np.full((h, w), 255, dtype=np.uint8)
    out = np.stack([r.astype(np.uint8), g.astype(np.uint8), b.astype(np.uint8), a], axis=-1)
    im = Image.fromarray(out, mode="RGBA")
    draw = ImageDraw.Draw(im, "RGBA")
    draw.rectangle([0, 0, w - 1, h - 1], outline=(222, 186, 112, 230), width=1)
    return clamp_song_ming_mineral_hsv(np.array(im, dtype=np.uint8))


def build_casket_tab_plate(active: bool) -> np.ndarray:
    w, h = 260, 58
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im, "RGBA")
    if active:
        draw.rounded_rectangle(
            [2, 2, w - 3, h - 9],
            radius=4,
            fill=(40, 32, 22, 252),
            outline=(214, 168, 90, 255),
            width=2,
        )
        draw.rounded_rectangle(
            [5, 5, w - 6, h - 12],
            radius=3,
            outline=(132, 102, 56, 170),
            width=1,
        )
        # Warm gilt underline bar (matching master_d_dao_casket.png active tab!)
        draw.rounded_rectangle(
            [18, h - 5, w - 19, h - 2],
            radius=2,
            fill=(224, 182, 102, 248),
        )
    else:
        draw.rounded_rectangle(
            [2, 4, w - 3, h - 9],
            radius=4,
            fill=(27, 23, 19, 242),
            outline=(108, 88, 60, 215),
            width=1,
        )
    return clamp_song_ming_mineral_hsv(np.array(im, dtype=np.uint8))


def build_casket_xuan_nameplate() -> np.ndarray:
    w, h = 240, 44
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im, "RGBA")
    draw.rounded_rectangle(
        [2, 3, w - 1, h - 1],
        radius=4,
        fill=(14, 12, 10, 130),
    )
    draw.rounded_rectangle(
        [0, 0, w - 4, h - 4],
        radius=4,
        fill=(232, 223, 206, 248),
        outline=(90, 62, 40, 255),
        width=2,
    )
    draw.rounded_rectangle(
        [3, 3, w - 7, h - 7],
        radius=2,
        outline=(182, 151, 102, 215),
        width=1,
    )
    return clamp_song_ming_mineral_hsv(np.array(im, dtype=np.uint8))


# ==============================================================================
# 5. Bronze Tripod Cauldron Stage (540x268), 8-Frame Flame Strip (1024x220),
#    Engraved Fire Gauge (860x54), Phase Seal (64x64), & Jade Ripple (256x256)
# ==============================================================================
def build_alchemy_cauldron_stage() -> np.ndarray:
    """2x-supersampled (1080x536 -> 540x268) bronze tripod cauldron with open hearth grate."""
    sw, sh = 1080, 536
    cx = 540.0
    im = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im, "RGBA")

    ink = (28, 23, 19, 255)
    bronze_dark = (74, 58, 38, 255)
    bronze_mid = (118, 94, 58, 255)
    bronze_hi = (188, 150, 88, 255)
    patina_jade = (68, 124, 104, 225)
    stone_dark = (52, 58, 56, 250)
    stone_mid = (82, 92, 88, 250)

    # Carved bluestone hearth plinth at bottom (y: 448..516)
    draw.ellipse([cx - 260, 456, cx + 260, 522], fill=(18, 15, 13, 155))
    plinth = [
        (cx - 228, 452),
        (cx + 228, 452),
        (cx + 252, 496),
        (cx - 252, 496),
    ]
    draw.polygon(plinth, fill=stone_mid, outline=ink, width=5)
    draw.polygon(
        [(cx - 252, 496), (cx + 252, 496), (cx + 238, 514), (cx - 238, 514)],
        fill=stone_dark,
        outline=ink,
        width=4,
    )
    # Hearth ash basin
    draw.ellipse([cx - 160, 458, cx + 160, 488], fill=(34, 28, 24, 235), outline=bronze_dark, width=3)

    # Three beast-paw bronze tripod legs (三足鼎立)
    for lx_off, ly_top, ly_bot, leg_w in [
        (-138, 346, 474, 38),
        (138, 346, 474, 38),
        (0, 368, 484, 34),
    ]:
        lx = cx + lx_off
        leg_poly = [
            (lx - leg_w, ly_top),
            (lx + leg_w, ly_top),
            (lx + leg_w * 0.72, ly_bot),
            (lx - leg_w * 0.72, ly_bot),
        ]
        draw.polygon(leg_poly, fill=bronze_dark, outline=ink, width=5)
        draw.ellipse(
            [lx - leg_w * 0.9, ly_top + 6, lx + leg_w * 0.9, ly_top + 42],
            fill=bronze_mid,
            outline=bronze_hi,
            width=3,
        )

    # Twin dragon-ear handles (双耳龙纹炉耳)
    for side in (-1.0, 1.0):
        ear_outer = [
            (cx + side * 176, 198),
            (cx + side * 256, 166),
            (cx + side * 268, 252),
            (cx + side * 196, 294),
        ]
        draw.polygon(ear_outer, fill=bronze_mid, outline=ink, width=5)
        ear_hole = [
            (cx + side * 194, 214),
            (cx + side * 238, 194),
            (cx + side * 244, 242),
            (cx + side * 204, 268),
        ]
        draw.polygon(ear_hole, fill=(0, 0, 0, 0), outline=bronze_hi, width=3)

    # Main spherical-squat bronze cauldron belly (y: 168..404)
    draw.ellipse(
        [cx - 196, 168, cx + 196, 408],
        fill=bronze_mid,
        outline=ink,
        width=6,
    )
    # Inner metallic shading & celadon verdigris band
    draw.ellipse([cx - 178, 184, cx + 178, 392], fill=bronze_dark)
    draw.ellipse([cx - 166, 192, cx + 148, 366], fill=bronze_mid)
    # Decorative Taotie / cloud-thunder waist band
    draw.rectangle([cx - 184, 254, cx + 184, 292], fill=patina_jade, outline=bronze_hi, width=3)
    for tx in range(int(cx - 160), int(cx + 161), 40):
        draw.rectangle([tx - 12, 262, tx + 12, 284], outline=bronze_hi, width=3)

    # Domed bronze lid & twin incense/pill-qi vents at (234*2, 58*2) & (306*2, 58*2)
    draw.ellipse([cx - 162, 118, cx + 162, 198], fill=bronze_mid, outline=ink, width=5)
    draw.rounded_rectangle([cx - 174, 158, cx + 174, 180], radius=8, fill=bronze_hi, outline=ink, width=4)
    # Central lotus finial knob + 2 flanking dragon vents
    draw.polygon(
        [(cx - 28, 120), (cx + 28, 120), (cx + 18, 82), (cx - 18, 82)],
        fill=bronze_hi,
        outline=ink,
        width=4,
    )
    draw.ellipse([cx - 22, 66, cx + 22, 92], fill=patina_jade, outline=ink, width=4)
    for vx in (cx - 72, cx + 72):
        draw.rounded_rectangle(
            [vx - 14, 102, vx + 14, 128],
            radius=5,
            fill=bronze_dark,
            outline=bronze_hi,
            width=3,
        )

    # Punch semi-transparent arched firebox window in lower belly (cx=540, cy=356)
    # AND punch ear holes cleanly so dynamic hearth flames shine vividly through!
    arr = np.array(im, dtype=np.uint8)
    yy, xx = np.mgrid[0:sh, 0:sw].astype(np.float32)
    firebox = ((xx - cx) / 96.0) ** 2 + ((yy - 358.0) / 54.0) ** 2 <= 1.0
    firebox = firebox & (yy <= 394.0)
    # Rim around firebox
    rim_mask = (
        (((xx - cx) / 106.0) ** 2 + ((yy - 358.0) / 62.0) ** 2 <= 1.0)
        & (~firebox)
        & (yy <= 398.0)
    )
    arr[rim_mask, :3] = np.array([196, 156, 90], dtype=np.uint8)
    arr[rim_mask, 3] = 255
    # Semi-transparent dark grate inside firebox so back-layer flames glow right through!
    arr[firebox, 0] = 24
    arr[firebox, 1] = 18
    arr[firebox, 2] = 15
    arr[firebox, 3] = 52
    # Vertical grate bars
    for gx in (-52, -26, 0, 26, 52):
        bar = firebox & (np.abs(xx - (cx + gx)) <= 3.5)
        arr[bar, :3] = np.array([42, 33, 25], dtype=np.uint8)
        arr[bar, 3] = 220

    return resize_premultiplied_rgba(arr, 540, 268)


def build_alchemy_flame_strip() -> np.ndarray:
    """8-frame (128x220 x 8 = 1024x220) Song-Ming Gongbi flickering flame strip."""
    fw, fh, frames = 128, 220, 8
    strip = np.zeros((fh, fw * frames, 4), dtype=np.uint8)

    for idx in range(frames):
        is_wu = idx >= 4
        local_i = idx % 4
        phase = local_i * (math.pi * 0.5)
        im = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
        draw = ImageDraw.Draw(im, "RGBA")

        base_y = 198.0
        cx = 64.0
        if not is_wu:
            # Frames 0..3: 文火 (Gentle simmering celadon-teal & warm amber core)
            outer_col = (74, 156, 144, 215)
            mid_col = (128, 196, 180, 235)
            core_col = (224, 206, 152, 245)
            tongues = 3
            h_main = 82.0 + math.sin(phase) * 10.0
            w_main = 26.0
        else:
            # Frames 4..7: 武火 (Roaring mineral-cinnabar, amber-gold & ivory-gold core)
            outer_col = (192, 74, 48, 238)
            mid_col = (216, 148, 66, 245)
            core_col = (234, 214, 150, 252)
            tongues = 5
            h_main = 166.0 + math.sin(phase) * 14.0
            w_main = 46.0

        for t_i in range(tongues):
            frac = (t_i / float(max(1, tongues - 1))) * 2.0 - 1.0 if tongues > 1 else 0.0
            tx = cx + frac * (w_main * 0.62)
            th = h_main * (1.0 - 0.28 * abs(frac))
            sway = math.sin(phase + t_i * 1.3) * (8.0 if not is_wu else 15.0)
            tw = (w_main * 0.48) * (1.0 - 0.18 * abs(frac))

            for sc, col in [(1.0, outer_col), (0.72, mid_col), (0.42, core_col)]:
                pts = [
                    (tx - tw * sc, base_y),
                    (tx - tw * sc * 0.85 + sway * 0.35, base_y - th * sc * 0.45),
                    (tx + sway * sc, base_y - th * sc),
                    (tx + tw * sc * 0.85 + sway * 0.35, base_y - th * sc * 0.45),
                    (tx + tw * sc, base_y),
                ]
                draw.polygon(pts, fill=col)

        im_blur = im.filter(ImageFilter.GaussianBlur(radius=1.6))
        strip[:, idx * fw : (idx + 1) * fw] = np.array(im_blur, dtype=np.uint8)

    return clamp_song_ming_mineral_hsv(strip)


def build_alchemy_fire_gauge_bg() -> np.ndarray:
    """860x54 (< 110px height!) carved ebony & gilt-bronze temperature gauge track."""
    w, h = 860, 54
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    t = xx / float(w - 1)

    # Subtle left-to-right mineral temperature undertone (celadon -> amber -> cinnabar)
    r = np.clip(26.0 + t * 34.0, 20.0, 68.0)
    g = np.clip(34.0 - np.abs(t - 0.45) * 12.0, 20.0, 42.0)
    b = np.clip(36.0 - t * 18.0, 16.0, 40.0)
    a = np.full((h, w), 250, dtype=np.uint8)
    arr = np.stack([r.astype(np.uint8), g.astype(np.uint8), b.astype(np.uint8), a], axis=-1)

    im = Image.fromarray(arr, mode="RGBA")
    draw = ImageDraw.Draw(im, "RGBA")
    draw.rounded_rectangle(
        [1, 1, w - 2, h - 2],
        radius=6,
        outline=(186, 148, 86, 255),
        width=2,
    )
    draw.rounded_rectangle(
        [4, 4, w - 5, h - 5],
        radius=4,
        outline=(92, 74, 48, 210),
        width=1,
    )
    # Ruler graduation ticks every 5%
    for pct in range(5, 100, 5):
        tx = int(round((pct / 100.0) * (w - 1)))
        major = (pct % 10) == 0
        th = 13 if major else 7
        col = (204, 166, 98, 220) if major else (132, 108, 72, 175)
        draw.line([tx, 5, tx, 5 + th], fill=col, width=2 if major else 1)
        draw.line([tx, h - 6 - th, tx, h - 6], fill=col, width=2 if major else 1)

    return clamp_song_ming_mineral_hsv(np.array(im, dtype=np.uint8))


def build_casket_seal_phase() -> np.ndarray:
    ss = 128
    im = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im, "RGBA")
    draw.rounded_rectangle(
        [12, 12, ss - 13, ss - 13],
        radius=18,
        fill=(158, 56, 44, 245),
        outline=(212, 172, 98, 255),
        width=5,
    )
    draw.rounded_rectangle(
        [22, 22, ss - 23, ss - 23],
        radius=12,
        outline=(232, 216, 188, 220),
        width=3,
    )
    draw.ellipse([42, 42, ss - 43, ss - 43], outline=(228, 198, 138, 220), width=4)
    return resize_premultiplied_rgba(np.array(im, dtype=np.uint8), 64, 64)


def build_casket_jade_ripple() -> np.ndarray:
    w, h = 256, 256
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    dx = (xx - 127.5) / 120.0
    dy = (yy - 127.5) / 120.0
    dist = np.sqrt(dx * dx + dy * dy)

    ring1 = np.exp(-((dist - 0.86) ** 2) / (2.0 * 0.045 ** 2))
    ring2 = np.exp(-((dist - 0.56) ** 2) / (2.0 * 0.040 ** 2)) * 0.78
    ring3 = np.exp(-((dist - 0.26) ** 2) / (2.0 * 0.038 ** 2)) * 0.55
    intensity = np.clip(ring1 + ring2 + ring3, 0.0, 1.0)

    r = np.clip(84.0 + intensity * 72.0, 0.0, 210.0)
    g = np.clip(168.0 + intensity * 56.0, 0.0, 232.0)
    b = np.clip(144.0 + intensity * 52.0, 0.0, 214.0)
    a = np.where(dist <= 1.02, np.clip(intensity * 238.0, 0.0, 238.0), 0.0)
    out = np.stack([r, g, b, a], axis=-1).astype(np.uint8)
    return clamp_song_ming_mineral_hsv(out)


# ==============================================================================
# 6. Provenance Contact Sheet, Manifest Registration & Self-Audit
# ==============================================================================
def build_provenance_contact_sheet(assets: dict[str, np.ndarray]) -> np.ndarray:
    cw, ch = 1920, 1440
    board = np.full((ch, cw, 4), (24, 21, 18, 255), dtype=np.uint8)

    def place_thumb(rel_key: str, x0: int, y0: int, tw: int, th: int) -> None:
        src = assets[rel_key]
        resized = resize_premultiplied_rgba(src, tw, th)
        roi = board[y0 : y0 + th, x0 : x0 + tw]
        alpha_over_np(roi, resized)
        board[y0 : y0 + th, x0 : x0 + tw] = roi

    place_thumb("project/assets/ui/frames/casket_ebony_outer_frame.png", 24, 24, 600, 338)
    place_thumb("project/assets/ui/frames/casket_xuan_tome_spread.png", 648, 24, 672, 338)
    place_thumb("project/assets/ui/frames/casket_page_flip_leaf.png", 1344, 24, 240, 338)
    place_thumb("project/assets/ui/frames/casket_meridian_figure.png", 1608, 24, 284, 340)

    place_thumb("project/assets/ui/frames/casket_slot_embossed.png", 24, 392, 144, 156)
    place_thumb("project/assets/ui/frames/casket_slot_selected.png", 188, 392, 144, 156)
    for idx, sk in enumerate(["weapon", "robe", "boots", "pendant", "treasure"]):
        place_thumb(
            f"project/assets/ui/icons/slot_silhouette_{sk}.png",
            360 + idx * 112,
            420,
            96,
            96,
        )
    place_thumb("project/assets/ui/icons/casket_acupoint_jade.png", 940, 436, 64, 64)
    place_thumb("project/assets/ui/icons/casket_seal_phase.png", 1024, 436, 64, 64)
    place_thumb("project/assets/ui/icons/casket_jade_ripple.png", 1116, 392, 180, 180)
    place_thumb("project/assets/ui/frames/casket_tab_active.png", 1324, 396, 260, 58)
    place_thumb("project/assets/ui/frames/casket_tab_inactive.png", 1324, 468, 260, 58)
    place_thumb("project/assets/ui/frames/casket_xuan_nameplate.png", 1608, 396, 240, 44)
    place_thumb("project/assets/ui/frames/casket_potential_bar_bg.png", 1608, 458, 260, 26)
    place_thumb("project/assets/ui/frames/casket_potential_bar_fill.png", 1608, 496, 252, 18)

    place_thumb("project/assets/ui/frames/alchemy_cauldron_stage.png", 24, 600, 540, 268)
    place_thumb("project/assets/ui/frames/alchemy_flame_strip.png", 588, 624, 1024, 220)
    place_thumb("project/assets/ui/frames/alchemy_fire_gauge_bg.png", 24, 904, 860, 54)

    return clamp_song_ming_mineral_hsv(board)


def update_asset_manifest(asset_meta: list[dict[str, str]]) -> int:
    manifest_path = os.path.join(REPO_ROOT, "docs", "asset-manifest.json")
    with open(manifest_path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)

    by_path: dict[str, dict[str, Any]] = {}
    for entry in doc.get("assets", []):
        rel_p = str(entry.get("path", ""))
        if rel_p and os.path.isfile(os.path.join(REPO_ROOT, rel_p)):
            by_path[rel_p] = entry

    for m in asset_meta:
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
            "license": LICENSE_R3,
        }

    doc["assets"] = [by_path[k] for k in sorted(by_path.keys())]
    with open(manifest_path, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    return len(doc["assets"])


def build_all() -> None:
    generated: dict[str, tuple[np.ndarray, str, str]] = {
        "project/assets/ui/frames/casket_ebony_outer_frame.png": (
            build_casket_ebony_outer_frame(),
            "ui_frame",
            "tools/build_polish_r3_ui.py (Carved dark-ebony outer casket frame with mitered Ruyi reliefs & recessed header trough aligned to master_d_dao_casket.png)",
        ),
        "project/assets/ui/frames/casket_xuan_tome_spread.png": (
            build_casket_xuan_tome_spread(),
            "ui_frame",
            "tools/build_polish_r3_ui.py (Open thread-bound aged Xuan-paper tome spread with stepped deckle paper edges, laid bamboo grain & silk stitches)",
        ),
        "project/assets/ui/frames/casket_page_flip_leaf.png": (
            build_casket_page_flip_leaf(),
            "ui_frame",
            "tools/build_polish_r3_ui.py (Shaded curling Xuan-paper page leaf for unfold and tab-switch page-flip transition)",
        ),
        "project/assets/ui/frames/casket_meridian_figure.png": (
            build_casket_meridian_figure(),
            "ui_frame",
            "tools/build_polish_r3_ui.py (2x-supersampled Song-Ming Gongbi brush-ink front human meridian figure with 8 glowing celadon-jade bi-disc acupoints, 0 baked text)",
        ),
        "project/assets/ui/frames/casket_slot_embossed.png": (
            build_casket_slot_card(False),
            "ui_frame",
            "tools/build_polish_r3_ui.py (2x-supersampled double-bordered antique-bronze embossed artifact slot card with corner filigree)",
        ),
        "project/assets/ui/frames/casket_slot_selected.png": (
            build_casket_slot_card(True),
            "ui_frame",
            "tools/build_polish_r3_ui.py (2x-supersampled embossed artifact slot card with warm mineral-gilt selection aura)",
        ),
        "project/assets/ui/frames/casket_potential_bar_bg.png": (
            build_casket_potential_bar_bg(),
            "ui_frame",
            "tools/build_polish_r3_ui.py (Carved dark bronze-ebony beveled trough for 5-stat potential gauges)",
        ),
        "project/assets/ui/frames/casket_potential_bar_fill.png": (
            build_casket_potential_bar_fill(),
            "ui_frame",
            "tools/build_polish_r3_ui.py (Beveled antique mineral-gold fill bar for 5-stat potential gauges)",
        ),
        "project/assets/ui/frames/casket_tab_active.png": (
            build_casket_tab_plate(True),
            "ui_frame",
            "tools/build_polish_r3_ui.py (Gilt-bordered dark-ebony active casket tab plaque with glowing underline bar)",
        ),
        "project/assets/ui/frames/casket_tab_inactive.png": (
            build_casket_tab_plate(False),
            "ui_frame",
            "tools/build_polish_r3_ui.py (Subdued bronze-hairline dark-ebony inactive casket tab plaque)",
        ),
        "project/assets/ui/frames/casket_xuan_nameplate.png": (
            build_casket_xuan_nameplate(),
            "ui_frame",
            "tools/build_polish_r3_ui.py (Aged Xuan-paper & bronze-corner scroll plaque for world Alt overhead nameplates)",
        ),
        "project/assets/ui/frames/alchemy_cauldron_stage.png": (
            build_alchemy_cauldron_stage(),
            "ui_frame",
            "tools/build_polish_r3_ui.py (2x-supersampled Song-Ming tripod dragon-ear bronze cauldron on bluestone plinth with open firebox grate)",
        ),
        "project/assets/ui/frames/alchemy_flame_strip.png": (
            build_alchemy_flame_strip(),
            "ui_frame",
            "tools/build_polish_r3_ui.py (8-frame Song-Ming calligraphic flickering hearth flame atlas: 4 Wen-fire celadon + 4 Wu-fire cinnabar-gold)",
        ),
        "project/assets/ui/frames/alchemy_fire_gauge_bg.png": (
            build_alchemy_fire_gauge_bg(),
            "ui_frame",
            "tools/build_polish_r3_ui.py (Carved dark-ebony & gilt-bronze graduated temperature gauge track)",
        ),
        "project/assets/ui/icons/casket_acupoint_jade.png": (
            build_casket_acupoint_jade(),
            "ui_icon",
            "tools/build_polish_r3_ui.py (2x-supersampled glowing celadon-jade circular bi-disc acupoint icon)",
        ),
        "project/assets/ui/icons/casket_seal_phase.png": (
            build_casket_seal_phase(),
            "ui_icon",
            "tools/build_polish_r3_ui.py (2x-supersampled cinnabar & gilt-bronze 3-phase alchemy cadence seal medallion)",
        ),
        "project/assets/ui/icons/casket_jade_ripple.png": (
            build_casket_jade_ripple(),
            "ui_icon",
            "tools/build_polish_r3_ui.py (Unshaded Song-Ming celadon-jade concentric water-ripple ring texture)",
        ),
    }
    slot_descs = {
        "weapon": "diagonal ancient longsword (佩兵)",
        "robe": "wide-sleeved cross-collar Daoist robe (法衣)",
        "boots": "cloud-scroll riding boots (履腕)",
        "pendant": "circular jade bi-disc pendant with silk cord (灵佩)",
        "treasure": "isometric carved sword casket (本命剑匣)",
    }
    for sk, sdesc in slot_descs.items():
        generated[f"project/assets/ui/icons/slot_silhouette_{sk}.png"] = (
            build_slot_silhouette(sk),
            "ui_icon",
            f"tools/build_polish_r3_ui.py (2x-supersampled Song-Ming monochrome brush-ink empty slot silhouette: {sdesc})",
        )

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
            "lossy_import_required": bool(
                reloaded.shape[1] > 1024 or reloaded.shape[0] > 1024
            ),
        }

    # Save provenance contact sheet & spec JSON under assets_src/ui/
    sheet_arr = build_provenance_contact_sheet(raw_arrays)
    sheet_full = os.path.join(REPO_ROOT, SOURCE_SHEET_REL)
    save_rgb_deterministic(sheet_arr, sheet_full)

    spec_doc = {
        "milestone": "M3_polish_r3_casket_interactions",
        "generated_date": GEN_DATE,
        "source_contact_sheet": SOURCE_SHEET_REL,
        "source_contact_sheet_sha256": sha256_file(sheet_full),
        "acupoints_local_460x550": {
            "baihui": [224, 36],
            "niwan": [224, 67],
            "shanzhong": [224, 222],
            "zhongwan": [224, 283],
            "qihai": [224, 334],
            "dantian": [224, 382],
            "laogong_left": [90, 382],
            "laogong_right": [358, 382],
        },
        "assets": audit_rows,
    }
    spec_full = os.path.join(REPO_ROOT, SOURCE_SPEC_REL)
    os.makedirs(os.path.dirname(spec_full), exist_ok=True)
    with open(spec_full, "w", encoding="utf-8") as fh:
        json.dump(spec_doc, fh, ensure_ascii=False, indent=2, sort_keys=True)
        fh.write("\n")

    total_registered = update_asset_manifest(meta_list)
    print(
        f"Polish R3 UI Build OK: {len(meta_list)} assets generated (0 fluorescent px), "
        f"{total_registered} total manifest entries verified."
    )


if __name__ == "__main__":
    build_all()
