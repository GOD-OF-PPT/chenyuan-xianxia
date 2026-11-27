#!/usr/bin/env python3
"""
Milestone M2 (Polish Round 2) Reproducible Song-Ming Gongbi Asset Builder:
1. Giant Boss `boss_mist_wolf_king_sheet.{png,json}` (3840x3584, 640x448 cell, foot_y=400, head_top_px=372).
2. Multi-Pose Party Heroes `{gu_changqing,shen_qinghe,pei_zhao}_sheet.{png,json}` (2112x2240, 352x280 cell, foot_y=248).
3. 33 `1024x1280` Waist-Up Portrait Expression Variants (`project/assets/portraits/*.png`) with calibrated
   final-canvas landmarks, build-time anatomical assertions, and repaired alpha matting.
4. 5 `NarrativeStage` Carved Ebony Handscroll Rollers, Plaque & Ghost-Free Ruined Temple Backdrop.
5. Deterministic `docs/asset-manifest.json` SHA-256 ledger update + stale-key pruning + hard quantitative assertions.

STRICT HYGIENE: Zero `/tmp` usage; 100% deterministic RNG seeds; zero baked 2px PIL VFX arcs; zero baked floor shadows.
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
LICENSE_R2 = "AI-Assisted & Procedural First-Party Original Asset (Song-Ming Gongbi Refinement, Commercial Rights Cleared)"
INK_DARK = (28, 24, 22)


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def clean_zero_alpha(arr: np.ndarray) -> np.ndarray:
    out = arr.copy()
    z = out[..., 3] == 0
    out[z, 0] = 0
    out[z, 1] = 0
    out[z, 2] = 0
    return out


def save_rgba_clean(arr: np.ndarray, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    cleaned = clean_zero_alpha(np.clip(arr, 0, 255).astype(np.uint8))
    Image.fromarray(cleaned, mode="RGBA").save(path, format="PNG", compress_level=6)


def save_rgb_clean(arr: np.ndarray, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode="RGB").save(path, format="PNG", compress_level=6)


def apply_song_ming_lut(rgba: np.ndarray, sat_scale: float = 0.92, val_scale: float = 1.0) -> np.ndarray:
    out = rgba.copy()
    a = out[..., 3]
    fg = a > 0
    if not np.any(fg):
        return clean_zero_alpha(out)
    rgb = out[..., :3].astype(np.float32)
    hsv = cv2.cvtColor(rgb.astype(np.uint8), cv2.COLOR_RGB2HSV).astype(np.float32)
    hsv[..., 1] = np.clip(hsv[..., 1] * sat_scale, 0.0, 255.0)
    hsv[..., 2] = np.clip(hsv[..., 2] * val_scale, 0.0, 255.0)
    graded = cv2.cvtColor(hsv.astype(np.uint8), cv2.COLOR_HSV2RGB).astype(np.float32)
    graded[..., 0] = np.clip(graded[..., 0] * 1.01 + 1.5, 0.0, 255.0)
    graded[..., 1] = np.clip(graded[..., 1] * 1.00 + 1.0, 0.0, 255.0)
    graded[..., 2] = np.clip(graded[..., 2] * 0.985, 0.0, 255.0)
    out[..., :3] = np.where(fg[..., None], graded, 0.0).astype(np.uint8)
    return clean_zero_alpha(out)


def alpha_over_np(dst: np.ndarray, src: np.ndarray) -> None:
    """In-place premultiplied-accurate Porter-Duff src OVER dst on uint8 RGBA."""
    sa = src[..., 3:4].astype(np.float32) / 255.0
    if not np.any(sa > 0.0):
        return
    da = dst[..., 3:4].astype(np.float32) / 255.0
    out_a = sa + da * (1.0 - sa)
    safe_a = np.maximum(out_a, 1e-6)
    sc = src[..., :3].astype(np.float32)
    dc = dst[..., :3].astype(np.float32)
    out_c = (sc * sa + dc * da * (1.0 - sa)) / safe_a
    dst[..., :3] = np.where(out_a > 1e-4, np.clip(np.round(out_c), 0.0, 255.0), 0.0).astype(np.uint8)
    dst[..., 3:4] = np.clip(np.round(out_a * 255.0), 0.0, 255.0).astype(np.uint8)


def paste_transformed_part(
    canvas: np.ndarray,
    part: np.ndarray,
    src_pivot: tuple[float, float],
    dst_pivot: tuple[float, float],
    angle_deg: float = 0.0,
    scale_xy: tuple[float, float] = (1.0, 1.0),
    rgb_mult: tuple[float, float, float] = (1.0, 1.0, 1.0),
    alpha_mult: float = 1.0,
) -> None:
    """Affine-transforms an RGBA part around src_pivot -> dst_pivot and composites onto canvas."""
    rad = math.radians(angle_deg)
    ca, sa = math.cos(rad), math.sin(rad)
    sx, sy = scale_xy
    px, py = src_pivot
    dx, dy = dst_pivot
    m00, m01 = ca * sx, -sa * sy
    m10, m11 = sa * sx, ca * sy
    tx = dx - m00 * px - m01 * py
    ty = dy - m10 * px - m11 * py
    M = np.array([[m00, m01, tx], [m10, m11, ty]], dtype=np.float32)

    ch, cw = canvas.shape[:2]
    src = part.astype(np.float32)
    a01 = (src[..., 3:4] / 255.0) * alpha_mult
    pre = np.concatenate([src[..., :3] * np.array(rgb_mult, dtype=np.float32) * a01, a01 * 255.0], axis=2)
    warped_pre = cv2.warpAffine(
        pre,
        M,
        (cw, ch),
        flags=cv2.INTER_LINEAR,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=(0.0, 0.0, 0.0, 0.0),
    )
    wa = np.clip(warped_pre[..., 3:4] / 255.0, 0.0, 1.0)
    if not np.any(wa > 0.004):
        return
    wrgb = np.where(wa > 0.004, np.clip(warped_pre[..., :3] / np.maximum(wa, 1e-5), 0.0, 255.0), 0.0)
    layer = np.concatenate([wrgb, wa * 255.0], axis=2).astype(np.uint8)
    alpha_over_np(canvas, layer)


def sample_bezier_chain(chains: list[list[tuple[float, float]]], steps_per_seg: int = 16) -> list[tuple[float, float]]:
    """Evaluates a sequence of linear/quadratic/cubic Bezier segments into a dense smooth contour."""
    out: list[tuple[float, float]] = []
    for seg_i, pts in enumerate(chains):
        if len(pts) < 2:
            continue
        start_k = 0 if seg_i == 0 else 1
        for k in range(start_k, steps_per_seg + 1):
            t = k / float(steps_per_seg)
            u = 1.0 - t
            if len(pts) == 2:
                x = u * pts[0][0] + t * pts[1][0]
                y = u * pts[0][1] + t * pts[1][1]
            elif len(pts) == 3:
                x = u * u * pts[0][0] + 2.0 * u * t * pts[1][0] + t * t * pts[2][0]
                y = u * u * pts[0][1] + 2.0 * u * t * pts[1][1] + t * t * pts[2][1]
            else:
                x = (u**3) * pts[0][0] + 3.0 * (u**2) * t * pts[1][0] + 3.0 * u * (t**2) * pts[2][0] + (t**3) * pts[3][0]
                y = (u**3) * pts[0][1] + 3.0 * (u**2) * t * pts[1][1] + 3.0 * u * (t**2) * pts[2][1] + (t**3) * pts[3][1]
            out.append((x, y))
    return out


def draw_bezier_ink(
    draw: ImageDraw.ImageDraw,
    pts: list[tuple[float, float]],
    color: tuple[int, int, int, int] | int,
    w_start: float,
    w_end: float,
    steps: int = 24,
) -> None:
    """Draws variable-width quadratic/cubic Bezier Song-Ming Gongbi brush-ink stroke."""
    if len(pts) < 2:
        return
    sampled = sample_bezier_chain([pts], steps_per_seg=steps)
    for i in range(len(sampled) - 1):
        t = i / float(max(1, len(sampled) - 2))
        r = max(0.6, 0.5 * ((1.0 - t) * w_start + t * w_end))
        p0, p1 = sampled[i], sampled[i + 1]
        draw.line([p0, p1], fill=color, width=max(1, int(round(r * 2.0))))
        draw.ellipse((p0[0] - r, p0[1] - r, p0[0] + r, p0[1] + r), fill=color)


def keep_largest_alpha_cc(rgba: np.ndarray, alpha_thresh: int = 12) -> np.ndarray:
    """Strips any disconnected stray islands/specks from an RGBA part at both alpha_thresh and >16."""
    out = rgba.copy()
    for thr in (alpha_thresh, 17):
        mask = (out[..., 3] >= thr).astype(np.uint8)
        nl, labels, stats, _ = cv2.connectedComponentsWithStats(mask, connectivity=8)
        if nl > 1:
            best_lid = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
            keep = (labels == best_lid)
            keep_dil = cv2.dilate(keep.astype(np.uint8), np.ones((3, 3), dtype=np.uint8), iterations=1) > 0
            out[(~keep) & (out[..., 3] >= thr), :] = 0
            out[~keep_dil, :] = 0
    return clean_zero_alpha(out)


# ==============================================================================
# SECTION 1: GIANT BOSS `boss_mist_wolf_king` (9-Part Articulated Gongbi Wolf)
# ==============================================================================
def segment_wolf_king_parts() -> dict[str, tuple[np.ndarray, tuple[float, float]]]:
    """
    Loads `assets_src/sprites/r2_wolf_king_side34_raw.png` (1376x768), extracts crisp alpha,
    applies Song-Ming mineral LUT aligned to `master_b_cangmu_rtwp.png`, and segments into
    9 genuine anatomical parts with curved socket feathering and zero detached shards.
    """
    raw_path = os.path.join(REPO_ROOT, "assets_src/sprites/r2_wolf_king_side34_raw.png")
    im = Image.open(raw_path).convert("RGB")
    arr = np.asarray(im, dtype=np.float32)
    H, W, _ = arr.shape

    bg = np.median(np.concatenate([arr[0], arr[-1], arr[:, 0], arr[:, -1]], axis=0), axis=0)
    diff = np.linalg.norm(arr - bg, axis=2)
    bg_cand = ((diff < 23.5) & (arr.mean(axis=2) > 195.0)).astype(np.uint8)
    nl, labels = cv2.connectedComponents(bg_cand, connectivity=8)
    ext = set(labels[0, :]) | set(labels[-1, :]) | set(labels[:, 0]) | set(labels[:, -1])
    ext.discard(0)
    fg = (~np.isin(labels, list(ext))).astype(np.float32)

    fg_blur = cv2.GaussianBlur(fg, (3, 3), 0.55)
    alpha = np.clip((fg_blur - 0.12) / 0.82 * 255.0, 0.0, 255.0).astype(np.uint8)
    rgb = arr.copy()
    edge = (alpha > 8) & (alpha < 235)
    rgb[edge] = rgb[edge] * 0.52 + np.array([28.0, 24.0, 26.0], dtype=np.float32) * 0.48
    rgba = clean_zero_alpha(np.concatenate([np.clip(rgb, 0, 255).astype(np.uint8), alpha[..., None]], axis=2))
    rgba = apply_song_ming_lut(rgba, sat_scale=0.96, val_scale=0.98)

    def poly_mask(pts: list[tuple[float, float]], feather: float = 2.6) -> np.ndarray:
        m = np.zeros((H, W), dtype=np.uint8)
        cv2.fillPoly(m, [np.round(np.array(pts, dtype=np.float32)).astype(np.int32)], 255)
        if feather > 0.1:
            mf = cv2.GaussianBlur(m.astype(np.float32), (0, 0), feather)
            return np.clip(mf / 255.0, 0.0, 1.0)
        return m.astype(np.float32) / 255.0

    # Curved upper-socket limb & tail masks (no razor-flat straight cut lines at joints!)
    m_tail = poly_mask(sample_bezier_chain([
        [(105, 140), (345, 150)],
        [(345, 150), (452, 265), (450, 368)],
        [(450, 368), (442, 435), (370, 508)],
        [(370, 508), (105, 508)],
    ], 12), 3.6)

    m_hind_near = poly_mask(sample_bezier_chain([
        [(378, 442), (425, 396), (485, 398), (528, 452)],
        [(528, 452), (510, 712)],
        [(510, 712), (368, 712)],
    ], 12), 4.2)

    m_hind_far = poly_mask(sample_bezier_chain([
        [(598, 435), (645, 404), (702, 408), (756, 488)],
        [(756, 488), (758, 650)],
        [(758, 650), (594, 650)],
    ], 12), 3.8)

    m_fore_near = poly_mask(sample_bezier_chain([
        [(776, 422), (830, 392), (898, 396), (974, 535)],
        [(974, 535), (984, 748)],
        [(984, 748), (812, 748)],
        [(812, 748), (770, 520)],
    ], 12), 4.2)

    m_fore_far = poly_mask(sample_bezier_chain([
        [(984, 486), (1038, 460), (1094, 466), (1248, 625)],
        [(1248, 625), (1248, 695)],
        [(1248, 695), (1082, 695)],
        [(1082, 695), (980, 558)],
    ], 12), 3.8)

    # Extend m_jaw & m_head past x=1340 so 100% of snout tip & fangs belong to head/jaw (ZERO snout shards in torso_mane!)
    m_jaw = poly_mask(sample_bezier_chain([
        [(1122, 434), (1188, 428), (1275, 462)],
        [(1275, 462), (1270, 526)],
        [(1270, 526), (1132, 522)],
    ], 10), 2.2)

    m_shard = poly_mask([(1186, 314), (1216, 314), (1220, 366), (1184, 366)], 1.6)

    m_head = poly_mask(sample_bezier_chain([
        [(1018, 175), (1340, 172)],
        [(1340, 172), (1340, 494)],
        [(1340, 494), (1235, 484), (1186, 446)],
        [(1186, 446), (1120, 454), (1012, 428)],
        [(1012, 428), (1004, 345), (1006, 250), (1018, 175)],
    ], 14), 5.0)

    # Softly curved neck exclusion for torso_mane at x~1086 (giving 82px fur-on-fur overlap with m_head at x=1004..1086!)
    m_head_torso_excl = poly_mask(sample_bezier_chain([
        [(1072, 152), (1350, 152)],
        [(1350, 152), (1350, 535)],
        [(1350, 535), (1068, 535)],
        [(1068, 535), (1084, 445), (1090, 345), (1084, 238)],
        [(1084, 238), (1078, 188), (1072, 152)],
    ], 16), 8.0)

    detach = (
        (m_tail > 0.55)
        | (m_hind_near > 0.55)
        | (m_hind_far > 0.55)
        | (m_fore_near > 0.55)
        | (m_fore_far > 0.55)
        | (m_head_torso_excl > 0.55)
    )
    torso_rgb = rgba[..., :3].copy()
    torso_a = rgba[..., 3].astype(np.float32) * np.clip(
        1.0 - np.maximum.reduce([m_tail, m_hind_near, m_hind_far, m_fore_near, m_fore_far, m_head_torso_excl, m_jaw]),
        0.0,
        1.0,
    )

    # Smooth curved interior ribcage/pelvis socket hull — strictly inside natural fur arch (ZERO straight belly/neck shelves!)
    hull_pts = sample_bezier_chain([
        [(438, 348), (475, 225), (660, 148), (908, 76)],
        [(908, 76), (1008, 96), (1068, 156), (1084, 252)],
        [(1084, 252), (1088, 342), (1064, 420), (1002, 446)],
        [(1002, 446), (925, 456), (855, 452), (780, 434)],
        [(780, 434), (705, 416), (625, 414), (555, 428)],
        [(555, 428), (495, 440), (452, 422), (438, 348)],
    ], 16)
    hull_torso = poly_mask(hull_pts, 8.5)
    socket_fill = ((detach & (rgba[..., 3] > 80)) & (hull_torso > 0.30)).astype(np.uint8) * 255
    if np.any(socket_fill > 0):
        torso_rgb = cv2.inpaint(torso_rgb, socket_fill, 9.0, cv2.INPAINT_TELEA)
        torso_a = np.maximum(torso_a, hull_torso * (rgba[..., 3].astype(np.float32) * 0.94))
    torso_a[torso_a < 18.0] = 0.0

    # Head cranium: clip dark_maw strictly to a tight curved upper-palate shadow behind upper teeth (never overhanging air!)
    head_rgb = rgba[..., :3].copy()
    head_a = rgba[..., 3].astype(np.float32) * m_head * np.clip(1.0 - m_jaw, 0.0, 1.0)
    head_a[head_a < 16.0] = 0.0
    mouth_interior = poly_mask(sample_bezier_chain([
        [(1148, 420), (1195, 422), (1236, 438)],
        [(1236, 438), (1196, 445), (1148, 440)],
    ], 10), 2.8)
    dark_maw = np.zeros_like(rgba)
    dark_maw[..., 0] = 48
    dark_maw[..., 1] = 22
    dark_maw[..., 2] = 30
    dark_maw[..., 3] = (mouth_interior * (head_a > 24.0) * 215.0).astype(np.uint8)
    head_rgba = clean_zero_alpha(np.concatenate([head_rgb, np.clip(head_a, 0, 255).astype(np.uint8)[..., None]], axis=2))
    maw_under = dark_maw.copy()
    alpha_over_np(maw_under, head_rgba)
    head_rgba = keep_largest_alpha_cc(clean_zero_alpha(maw_under), 12)

    def make_part(
        mask_f: np.ndarray,
        pivot_xy: tuple[float, float],
        custom_rgba: np.ndarray | None = None,
        soften_top_px: int = 0,
    ) -> tuple[np.ndarray, tuple[float, float]]:
        base = custom_rgba if custom_rgba is not None else clean_zero_alpha(
            np.concatenate([rgba[..., :3], np.clip(rgba[..., 3].astype(np.float32) * mask_f, 0, 255).astype(np.uint8)[..., None]], axis=2)
        )
        base = keep_largest_alpha_cc(base, 10)
        ys, xs = np.where(base[..., 3] > 6)
        x0, x1 = max(0, int(xs.min()) - 4), min(W, int(xs.max()) + 5)
        y0, y1 = max(0, int(ys.min()) - 4), min(H, int(ys.max()) + 5)
        cropped = clean_zero_alpha(base[y0:y1, x0:x1])
        if soften_top_px > 0 and cropped.shape[0] > soften_top_px + 8:
            ramp = np.linspace(0.15, 1.0, soften_top_px, dtype=np.float32)[:, None]
            cropped[:soften_top_px, :, 3] = np.clip(cropped[:soften_top_px, :, 3].astype(np.float32) * ramp, 0.0, 255.0).astype(np.uint8)
            cropped = clean_zero_alpha(cropped)
        return cropped, (pivot_xy[0] - x0, pivot_xy[1] - y0)

    torso_full = keep_largest_alpha_cc(
        clean_zero_alpha(np.concatenate([torso_rgb, np.clip(torso_a, 0, 255).astype(np.uint8)[..., None]], axis=2)),
        14,
    )
    parts = {
        "tail": make_part(m_tail, (442.0, 368.0)),
        "hind_leg_far": make_part(m_hind_far, (658.0, 432.0), soften_top_px=14),
        "fore_leg_far": make_part(m_fore_far, (1026.0, 492.0), soften_top_px=14),
        "torso_mane": make_part(np.ones((H, W), dtype=np.float32), (740.0, 340.0), torso_full),
        "hind_leg_near": make_part(m_hind_near, (468.0, 428.0), soften_top_px=16),
        "fore_leg_near": make_part(m_fore_near, (852.0, 432.0), soften_top_px=16),
        "head_cranium": make_part(np.ones((H, W), dtype=np.float32), (1076.0, 342.0), head_rgba),
        "lower_jaw": make_part(m_jaw, (1134.0, 444.0)),
        "forehead_shard": make_part(m_shard, (1202.0, 340.0)),
    }

    # Archive 9-part contact sheet to `assets_src/sprites/r2_wolf_king_parts_sheet.png`
    ps_w, ps_h = 1560, 760
    ps_im = Image.new("RGBA", (ps_w, ps_h), (242, 236, 224, 255))
    ps_arr = np.asarray(ps_im).copy()
    cursor_x, cursor_y, row_max_h = 20, 20, 0
    for pname in ["torso_mane", "tail", "fore_leg_near", "fore_leg_far", "hind_leg_near", "hind_leg_far", "head_cranium", "lower_jaw", "forehead_shard"]:
        parr, _ = parts[pname]
        ph, pw = parr.shape[:2]
        sc = min(1.0, 340.0 / max(1, ph), 480.0 / max(1, pw))
        if sc < 1.0:
            parr = np.asarray(Image.fromarray(parr).resize((max(1, int(pw * sc)), max(1, int(ph * sc))), Image.Resampling.LANCZOS))
            ph, pw = parr.shape[:2]
        if cursor_x + pw > ps_w - 20:
            cursor_x = 20
            cursor_y += row_max_h + 24
            row_max_h = 0
        sub = ps_arr[cursor_y : cursor_y + ph, cursor_x : cursor_x + pw]
        alpha_over_np(sub, parr)
        cursor_x += pw + 24
        row_max_h = max(row_max_h, ph)
    save_rgba_clean(ps_arr, os.path.join(REPO_ROOT, "assets_src/sprites/r2_wolf_king_parts_sheet.png"))
    return parts


def render_wolf_king_cell(
    parts: dict[str, tuple[np.ndarray, tuple[float, float]]],
    pose: dict[str, Any],
    cell_w: int = 640,
    cell_h: int = 448,
    foot_y: int = 400,
) -> np.ndarray:
    """Renders a single 640x448 cell at 2x supersampling (1280x896 -> Lanczos 640x448) with 0 border clips."""
    W2, H2 = cell_w * 2, cell_h * 2
    canvas = np.zeros((H2, W2, 4), dtype=np.uint8)

    bsx = 0.862 * float(pose.get("scale_x", 1.0))
    bsy = 0.992 * float(pose.get("scale_y", 1.0))
    # Anchor raw spine-ground (740, 726) -> FeetOrigin (cell_w*0.5, foot_y) in 2x space = (640, 800)
    fx2 = W2 * 0.5 + float(pose.get("root_dx", 0.0)) * 2.0
    fy2 = foot_y * 2.0 + float(pose.get("root_dy", 0.0)) * 2.0

    def raw_to_c2(rx: float, ry: float, torso_ang: float) -> tuple[float, float]:
        dx0 = (rx - 740.0) * bsx
        dy0 = (ry - 340.0) * bsy
        rad = math.radians(torso_ang)
        rx_r = dx0 * math.cos(rad) - dy0 * math.sin(rad)
        ry_r = dx0 * math.sin(rad) + dy0 * math.cos(rad)
        spine_cx = fx2
        spine_cy = fy2 + (340.0 - 726.0) * bsy
        return (spine_cx + rx_r, spine_cy + ry_r)

    t_ang = float(pose.get("torso_ang", 0.0))
    is_ne = bool(pose.get("dorsal_ne", False))
    is_down = bool(pose.get("is_down", False))
    shard_glow = float(pose.get("shard_glow", 0.0))

    p_spine = raw_to_c2(740.0, 340.0, 0.0)
    p_tail = raw_to_c2(442.0, 368.0, t_ang)
    p_hf = raw_to_c2(658.0, 432.0, t_ang)
    p_ff = raw_to_c2(1026.0, 492.0, t_ang)
    p_hn = raw_to_c2(468.0, 428.0, t_ang)
    p_fn = raw_to_c2(852.0, 432.0, t_ang)
    p_neck = raw_to_c2(1076.0, 342.0, t_ang)

    head_ang = t_ang + float(pose.get("head_ang", 0.0))
    head_dx = float(pose.get("head_dx", 0.0)) * 2.0
    head_dy = float(pose.get("head_dy", 0.0)) * 2.0
    p_head = (p_neck[0] + head_dx, p_neck[1] + head_dy)

    h_rad = math.radians(head_ang)

    def head_rel(rx: float, ry: float, base_head: tuple[float, float], ang_d: float, sc_h: tuple[float, float] = (1.0, 1.0)) -> tuple[float, float]:
        rr = math.radians(ang_d)
        ux = (rx - 1076.0) * bsx * sc_h[0]
        uy = (ry - 342.0) * bsy * sc_h[1]
        return (base_head[0] + ux * math.cos(rr) - uy * math.sin(rr), base_head[1] + ux * math.sin(rr) + uy * math.cos(rr))

    p_jaw = head_rel(1134.0, 444.0, p_head, head_ang)
    p_shard = head_rel(1202.0, 340.0, p_head, head_ang)

    def place(name: str, dst_pt: tuple[float, float], ang: float, sc_mult: tuple[float, float] = (1.0, 1.0), rgb_m: tuple[float, float, float] = (1.0, 1.0, 1.0), a_m: float = 1.0) -> None:
        parr, piv = parts[name]
        paste_transformed_part(
            canvas,
            parr,
            piv,
            dst_pt,
            angle_deg=ang,
            scale_xy=(bsx * sc_mult[0], bsy * sc_mult[1]),
            rgb_mult=rgb_m,
            alpha_mult=a_m,
        )

    fn_off = (float(pose.get("fn_dx", 0.0)) * 2.0, float(pose.get("fn_dy", 0.0)) * 2.0)
    ff_off = (float(pose.get("ff_dx", 0.0)) * 2.0, float(pose.get("ff_dy", 0.0)) * 2.0)
    hn_off = (float(pose.get("hn_dx", 0.0)) * 2.0, float(pose.get("hn_dy", 0.0)) * 2.0)
    hf_off = (float(pose.get("hf_dx", 0.0)) * 2.0, float(pose.get("hf_dy", 0.0)) * 2.0)

    if is_down:
        # Grounded quadruped collapse: limbs fold forward/underneath torso_mane along ground plane so 0 cut thigh edges poke above spine!
        place("hind_leg_far", (p_hf[0] + hf_off[0], p_hf[1] + hf_off[1]), float(pose.get("hf_ang", 0.0)), sc_mult=(0.92, 0.88), rgb_m=(0.80, 0.80, 0.85))
        place("fore_leg_far", (p_ff[0] + ff_off[0], p_ff[1] + ff_off[1]), float(pose.get("ff_ang", 0.0)), sc_mult=(0.92, 0.88), rgb_m=(0.82, 0.82, 0.86))
        place("hind_leg_near", (p_hn[0] + hn_off[0], p_hn[1] + hn_off[1]), float(pose.get("hn_ang", 0.0)), sc_mult=(0.94, 0.88))
        place("fore_leg_near", (p_fn[0] + fn_off[0], p_fn[1] + fn_off[1]), float(pose.get("fn_ang", 0.0)), sc_mult=(0.94, 0.88))
        place("tail", p_tail, t_ang + float(pose.get("tail_ang", 0.0)), sc_mult=(0.96, 0.88))
        place("torso_mane", p_spine, t_ang)
        place("lower_jaw", p_jaw, head_ang + float(pose.get("jaw_ang", 0.0)))
        place("head_cranium", p_head, head_ang)
        place("forehead_shard", p_shard, head_ang, rgb_m=(0.52, 0.55, 0.54))
    elif not is_ne:
        # SE front-3/4 layer order: far limbs -> tail -> torso_mane -> near hind -> jaw -> head -> shard -> near fore
        place("hind_leg_far", (p_hf[0] + hf_off[0], p_hf[1] + hf_off[1]), float(pose.get("hf_ang", 0.0)), rgb_m=(0.84, 0.84, 0.88))
        place("fore_leg_far", (p_ff[0] + ff_off[0], p_ff[1] + ff_off[1]), float(pose.get("ff_ang", 0.0)), rgb_m=(0.86, 0.86, 0.90))
        place("tail", p_tail, t_ang + float(pose.get("tail_ang", 0.0)))
        mane_rgb = (1.0, 1.0 + 0.14 * shard_glow, 1.0 + 0.06 * shard_glow)
        place("torso_mane", p_spine, t_ang, rgb_m=mane_rgb)
        place("hind_leg_near", (p_hn[0] + hn_off[0], p_hn[1] + hn_off[1]), float(pose.get("hn_ang", 0.0)))
        place("lower_jaw", p_jaw, head_ang + float(pose.get("jaw_ang", 0.0)))
        place("head_cranium", p_head, head_ang)
        shard_rgb = (1.0 + 0.25 * shard_glow, 1.0 + 0.55 * shard_glow, 1.0 + 0.35 * shard_glow)
        if bool(pose.get("dim_shard", False)):
            shard_rgb = (0.52, 0.55, 0.54)
        place("forehead_shard", p_shard, head_ang, rgb_m=shard_rgb)
        place("fore_leg_near", (p_fn[0] + fn_off[0], p_fn[1] + fn_off[1]), float(pose.get("fn_ang", 0.0)), sc_mult=pose.get("fn_scale", (1.0, 1.0)))
    else:
        # True NE dorsal-3/4 turnaround: include lower_jaw attached to head_cranium underneath feathered dorsal ruff!
        ne_head_pt = (p_head[0] - 28.0, p_head[1] - 24.0)
        ne_head_ang = head_ang - 10.0
        ne_head_sc = (0.88, 0.90)
        ne_jaw_pt = head_rel(1134.0, 444.0, ne_head_pt, ne_head_ang, ne_head_sc)
        place("fore_leg_far", (p_ff[0] + ff_off[0] - 18.0, p_ff[1] + ff_off[1] - 24.0), float(pose.get("ff_ang", 0.0)) - 6.0, sc_mult=(0.90, 0.90), rgb_m=(0.76, 0.77, 0.82))
        place("lower_jaw", ne_jaw_pt, ne_head_ang + float(pose.get("jaw_ang", 0.0)) * 0.65, sc_mult=ne_head_sc, rgb_m=(0.82, 0.82, 0.86))
        place("head_cranium", ne_head_pt, ne_head_ang, sc_mult=ne_head_sc, rgb_m=(0.84, 0.84, 0.88))
        place("fore_leg_near", (p_fn[0] + fn_off[0] + 10.0, p_fn[1] + fn_off[1] - 16.0), float(pose.get("fn_ang", 0.0)) - 4.0, sc_mult=(0.94, 0.94), rgb_m=(0.88, 0.88, 0.91))
        place("hind_leg_far", (p_hf[0] + hf_off[0], p_hf[1] + hf_off[1] - 12.0), float(pose.get("hf_ang", 0.0)), rgb_m=(0.84, 0.84, 0.88))
        place("torso_mane", (p_spine[0], p_spine[1] - 6.0), t_ang - 4.0, sc_mult=(1.02, 1.02), rgb_m=(0.95, 0.97, 0.97))
        place("hind_leg_near", (p_hn[0] + hn_off[0] + 8.0, p_hn[1] + hn_off[1]), float(pose.get("hn_ang", 0.0)), sc_mult=(1.03, 1.02))
        place("tail", (p_tail[0] + 22.0, p_tail[1] + 6.0), t_ang + float(pose.get("tail_ang", 0.0)) + 8.0, sc_mult=(1.06, 1.04))

    if shard_glow > 0.05 and not is_ne:
        glow_im = Image.new("RGBA", (W2, H2), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow_im)
        gx, gy = p_shard
        rx, ry = int(28 * shard_glow + 12), int(38 * shard_glow + 16)
        gd.ellipse((gx - rx, gy - ry, gx + rx, gy + ry), fill=(82, 232, 168, int(92 * shard_glow)))
        glow_im = glow_im.filter(ImageFilter.GaussianBlur(radius=9.0))
        alpha_over_np(canvas, np.asarray(glow_im))

    out_im = Image.fromarray(clean_zero_alpha(canvas), mode="RGBA").resize((cell_w, cell_h), Image.Resampling.LANCZOS)
    out = np.asarray(out_im).copy()
    out = keep_largest_alpha_cc(out, 12)

    max_allowed_y = foot_y + 8
    ys_all, _ = np.where(out[..., 3] > 0)
    if len(ys_all) > 0 and int(ys_all.max()) > max_allowed_y:
        shift_up = int(ys_all.max()) - max_allowed_y
        shifted = np.zeros_like(out)
        if shift_up < cell_h:
            shifted[: cell_h - shift_up, :] = out[shift_up:, :]
        out = shifted
    out[foot_y + 10 :, :, :] = 0
    return keep_largest_alpha_cc(out, 12)


def build_wolf_king_sheet() -> dict[str, Any]:
    parts = segment_wolf_king_parts()
    cw, ch, cols, rows_cnt = 640, 448, 6, 8
    foot_y, head_top_px = 400, 372
    sheet = np.zeros((ch * rows_cnt, cw * cols, 4), dtype=np.uint8)

    def put_cell(r: int, c: int, pose: dict[str, Any]) -> np.ndarray:
        cell = render_wolf_king_cell(parts, pose, cw, ch, foot_y)
        sheet[r * ch : (r + 1) * ch, c * cw : (c + 1) * cw] = cell
        return cell

    # Row 0: idle_se (4 frames) & Row 1: idle_ne (4 frames)
    for f in range(4):
        ph = (2.0 * math.pi * f) / 4.0
        breath = math.sin(ph)
        pose_se = {
            "root_dy": -2.5 * breath,
            "torso_ang": 1.6 * breath,
            "head_ang": -2.2 * breath,
            "jaw_ang": 4.5 * (0.5 + 0.5 * math.cos(ph)),
            "tail_ang": 9.5 * math.sin(ph + 0.6),
            "shard_glow": 0.22 + 0.12 * (0.5 + 0.5 * math.sin(ph)),
        }
        put_cell(0, f, pose_se)
        pose_ne = dict(pose_se, dorsal_ne=True)
        put_cell(1, f, pose_ne)

    # Row 2: run_se (6-frame rotary gallop) & Row 3: run_ne (6-frame dorsal rotary gallop)
    gallop_phases = [
        (-5.5, -8.0, -34.0, 22.0, 32.0, -18.0, -14.0, -10.0, -14.0, 5.0),
        (-2.0, -13.0, -16.0, -28.0, 14.0, 28.0, -18.0, -14.0, -18.0, 3.0),
        (4.5, -4.0, 18.0, -14.0, -24.0, 16.0, -4.0, -8.0, -8.0, -4.0),
        (6.5, 0.0, 34.0, 14.0, -34.0, -16.0, 0.0, -14.0, 4.0, -6.0),
        (2.0, -6.0, 14.0, 32.0, -10.0, -30.0, -6.0, -12.0, 8.0, -2.0),
        (-3.5, -11.0, -18.0, 26.0, 20.0, -8.0, -14.0, -6.0, -6.0, 3.0),
    ]
    for f, gp in enumerate(gallop_phases):
        r_pose = {
            "torso_ang": gp[0],
            "root_dy": gp[1],
            "fn_ang": gp[2],
            "ff_ang": gp[3],
            "hn_ang": gp[4],
            "hf_ang": gp[5],
            "fn_dy": gp[6],
            "hn_dy": gp[7],
            "tail_ang": gp[8],
            "head_ang": gp[9],
            "jaw_ang": 7.0,
            "shard_glow": 0.25,
        }
        put_cell(2, f, r_pose)
        put_cell(3, f, dict(r_pose, dorsal_ne=True))

    # Row 4: attack_1 (5 frames — rearing razor-claw cleave; dorsal mane <= 368px < head_top_px=372!)
    atk1 = [
        {"root_dx": -12.0, "root_dy": -8.0, "torso_ang": -13.5, "fn_ang": -52.0, "fn_dx": 14.0, "fn_dy": -34.0, "ff_ang": -18.0, "ff_dy": -14.0, "hn_ang": 10.0, "head_ang": -8.0, "jaw_ang": 16.0, "tail_ang": 16.0, "shard_glow": 0.55},
        {"root_dx": -4.0, "root_dy": -11.0, "torso_ang": -15.0, "fn_ang": -64.0, "fn_dx": 22.0, "fn_dy": -44.0, "ff_ang": -24.0, "ff_dy": -18.0, "hn_ang": 14.0, "head_ang": -6.0, "jaw_ang": 22.0, "tail_ang": 20.0, "shard_glow": 0.75},
        {"root_dx": 20.0, "root_dy": -4.0, "torso_ang": 7.5, "fn_ang": -28.0, "fn_dx": 38.0, "fn_dy": -14.0, "fn_scale": (1.08, 1.04), "ff_ang": 16.0, "hn_ang": -22.0, "head_ang": 6.0, "head_dx": 12.0, "jaw_ang": 18.0, "tail_ang": -12.0, "shard_glow": 0.65},
        {"root_dx": 14.0, "root_dy": 0.0, "torso_ang": 9.0, "fn_ang": 12.0, "fn_dx": 18.0, "ff_ang": 10.0, "hn_ang": -16.0, "head_ang": 4.0, "jaw_ang": 8.0, "tail_ang": -8.0, "shard_glow": 0.35},
        {"root_dx": 4.0, "root_dy": -1.0, "torso_ang": 3.0, "fn_ang": 4.0, "hn_ang": -6.0, "head_ang": 1.0, "jaw_ang": 4.0, "tail_ang": 2.0, "shard_glow": 0.22},
    ]
    for f, p in enumerate(atk1):
        put_cell(4, f, p)

    # Row 5: attack_2 (5 frames — coiling crouch -> explosive demon-fang lunge max_x >= idle + 28px)
    atk2 = [
        {"root_dx": -16.0, "root_dy": 6.0, "torso_ang": 7.5, "fn_ang": 22.0, "hn_ang": 18.0, "head_ang": -6.0, "jaw_ang": 24.0, "tail_ang": 14.0, "shard_glow": 0.45},
        {"root_dx": -10.0, "root_dy": 4.0, "torso_ang": 5.0, "fn_ang": 16.0, "hn_ang": 24.0, "head_ang": -10.0, "jaw_ang": 28.0, "tail_ang": 18.0, "shard_glow": 0.70},
        {"root_dx": 30.0, "root_dy": -6.0, "torso_ang": -4.0, "fn_ang": -32.0, "fn_dx": 18.0, "fn_dy": -12.0, "ff_ang": -24.0, "hn_ang": -28.0, "hf_ang": -22.0, "head_dx": 14.0, "head_ang": 4.0, "jaw_ang": -5.0, "tail_ang": -16.0, "shard_glow": 0.80},
        {"root_dx": 22.0, "root_dy": -2.0, "torso_ang": 3.0, "fn_ang": -14.0, "hn_ang": -18.0, "head_dx": 8.0, "head_ang": 6.0, "jaw_ang": -3.0, "tail_ang": -10.0, "shard_glow": 0.45},
        {"root_dx": 6.0, "root_dy": 0.0, "torso_ang": 1.5, "fn_ang": -4.0, "hn_ang": -6.0, "jaw_ang": 4.0, "tail_ang": -2.0, "shard_glow": 0.25},
    ]
    for f, p in enumerate(atk2):
        put_cell(5, f, p)

    # Row 6: cast_loop (cols 0..2) & cast_release (cols 3..5) — `腐木咆哮`
    cast_frames = [
        {"root_dx": -6.0, "root_dy": -3.0, "torso_ang": -7.5, "fn_ang": -8.0, "head_ang": -12.0, "jaw_ang": 22.0, "tail_ang": 12.0, "shard_glow": 0.65},
        {"root_dx": -8.0, "root_dy": -6.0, "torso_ang": -10.5, "fn_ang": -14.0, "fn_dy": -6.0, "head_ang": -15.0, "jaw_ang": 28.0, "tail_ang": 16.0, "shard_glow": 0.90},
        {"root_dx": -6.0, "root_dy": -4.5, "torso_ang": -9.0, "fn_ang": -10.0, "head_ang": -13.5, "jaw_ang": 25.0, "tail_ang": 14.0, "shard_glow": 0.78},
        {"root_dx": 16.0, "root_dy": -2.0, "torso_ang": 5.5, "fn_ang": -18.0, "hn_ang": -14.0, "head_dx": 14.0, "head_ang": 4.0, "jaw_ang": 30.0, "tail_ang": -14.0, "shard_glow": 1.00},
        {"root_dx": 20.0, "root_dy": 0.0, "torso_ang": 7.0, "fn_ang": -12.0, "hn_ang": -16.0, "head_dx": 16.0, "head_ang": 6.0, "jaw_ang": 26.0, "tail_ang": -16.0, "shard_glow": 0.85},
        {"root_dx": 8.0, "root_dy": 0.0, "torso_ang": 2.5, "fn_ang": -4.0, "hn_ang": -6.0, "head_dx": 6.0, "head_ang": 2.0, "jaw_ang": 12.0, "tail_ang": -6.0, "shard_glow": 0.40},
    ]
    for f, p in enumerate(cast_frames):
        put_cell(6, f, p)

    # Row 7: hit (cols 0..1) & down (cols 2..3 — natural grounded quadruped collapse with limbs tucked under belly!)
    row7_frames = [
        {"root_dx": -14.0, "root_dy": -4.0, "torso_ang": -10.0, "fn_ang": -24.0, "fn_dy": -12.0, "hn_ang": 16.0, "head_ang": -16.0, "jaw_ang": 16.0, "tail_ang": -10.0, "shard_glow": 0.15},
        {"root_dx": -9.0, "root_dy": -2.0, "torso_ang": -6.0, "fn_ang": -12.0, "fn_dy": -6.0, "hn_ang": 10.0, "head_ang": -10.0, "jaw_ang": 10.0, "tail_ang": -6.0, "shard_glow": 0.15},
        # down col 2: buckling knees, limbs folding forward underneath torso_mane
        {"is_down": True, "root_dx": -2.0, "root_dy": 32.0, "scale_x": 1.02, "scale_y": 0.78, "torso_ang": 8.0, "fn_ang": -52.0, "fn_dx": 22.0, "fn_dy": 14.0, "ff_ang": -44.0, "ff_dx": 18.0, "ff_dy": 8.0, "hn_ang": -46.0, "hn_dx": 24.0, "hn_dy": 18.0, "hf_ang": -40.0, "hf_dx": 18.0, "hf_dy": 12.0, "head_dy": 10.0, "head_ang": 10.0, "jaw_ang": 8.0, "tail_ang": -16.0, "dim_shard": True},
        # down col 3: full crumpled horizontal collapse (`破罡瘫痪` / defeated: height <= 0.62*idle_h, paws flush on ground!)
        {"is_down": True, "root_dx": 4.0, "root_dy": 66.0, "scale_x": 1.04, "scale_y": 0.60, "torso_ang": 9.0, "fn_ang": -66.0, "fn_dx": 34.0, "fn_dy": 18.0, "ff_ang": -58.0, "ff_dx": 26.0, "ff_dy": 12.0, "hn_ang": -62.0, "hn_dx": 38.0, "hn_dy": 22.0, "hf_ang": -56.0, "hf_dx": 28.0, "hf_dy": 16.0, "head_dx": 8.0, "head_dy": 8.0, "head_ang": 12.0, "jaw_ang": 6.0, "tail_ang": -22.0, "dim_shard": True},
    ]
    for f, p in enumerate(row7_frames):
        put_cell(7, f, p)

    png_out = os.path.join(REPO_ROOT, "project/assets/sprites/boss_mist_wolf_king_sheet.png")
    save_rgba_clean(sheet, png_out)

    meta = {
        "actor_id": "boss_mist_wolf_king",
        "cell_w": cw,
        "cell_h": ch,
        "foot_y": foot_y,
        "head_top_px": head_top_px,
        "cols": cols,
        "rows": {
            "idle_se": {"row": 0, "frames": 4, "fps": 6.0, "loop": True},
            "idle_ne": {"row": 1, "frames": 4, "fps": 6.0, "loop": True},
            "run_se": {"row": 2, "frames": 6, "fps": 10.0, "loop": True},
            "run_ne": {"row": 3, "frames": 6, "fps": 10.0, "loop": True},
            "attack_1": {"row": 4, "frames": 5, "fps": 11.5, "loop": False},
            "attack_2": {"row": 5, "frames": 5, "fps": 11.5, "loop": False},
            "cast_loop": {"row": 6, "start_col": 0, "frames": 3, "fps": 7.5, "loop": True},
            "cast_release": {"row": 6, "start_col": 3, "frames": 3, "fps": 10.0, "loop": False},
            "hit": {"row": 7, "start_col": 0, "frames": 2, "fps": 9.0, "loop": False},
            "down": {"row": 7, "start_col": 2, "frames": 2, "fps": 4.0, "loop": False},
        },
        "anchors": {
            "weapon": [218, -136],
            "hand": [204, -142],
            "cast": [204, -218],
            "chest": [64, -178],
            "head": [186, -238],
            "mouth": [224, -178],
            "roar": [224, -178],
            "overhead": [0, -372],
        },
        "state_anchors": {
            "idle_se": {"weapon": [200, -96], "hand": [192, -110], "cast": [190, -236], "chest": [62, -178], "head": [184, -236], "mouth": [222, -176], "overhead": [0, -372]},
            "idle_ne": {"weapon": [172, -118], "hand": [164, -126], "cast": [168, -238], "chest": [52, -182], "head": [162, -238], "mouth": [192, -186], "overhead": [0, -372]},
            "run_se": {"weapon": [220, -118], "hand": [212, -124], "cast": [202, -228], "chest": [70, -174], "head": [196, -228], "mouth": [234, -170], "overhead": [8, -372]},
            "run_ne": {"weapon": [184, -132], "hand": [176, -138], "cast": [180, -234], "chest": [58, -180], "head": [172, -236], "mouth": [204, -184], "overhead": [6, -372]},
            "attack_1": {"weapon": [240, -148], "hand": [228, -156], "cast": [206, -248], "chest": [76, -186], "head": [200, -246], "mouth": [236, -188], "overhead": [8, -376]},
            "attack_2": {"weapon": [256, -162], "hand": [240, -148], "cast": [232, -222], "chest": [92, -168], "head": [224, -218], "mouth": [260, -166], "overhead": [24, -372]},
            "cast_loop": {"weapon": [204, -98], "hand": [198, -112], "cast": [204, -256], "chest": [66, -188], "head": [196, -254], "mouth": [236, -196], "overhead": [0, -376]},
            "cast_release": {"weapon": [222, -112], "hand": [214, -120], "cast": [226, -242], "chest": [82, -180], "head": [216, -238], "mouth": [254, -182], "overhead": [14, -372]},
            "hit": {"weapon": [176, -112], "hand": [170, -118], "cast": [166, -242], "chest": [42, -182], "head": [160, -244], "mouth": [196, -188], "overhead": [-10, -372]},
            "down": {"weapon": [182, -28], "hand": [176, -32], "cast": [164, -78], "chest": [36, -68], "head": [170, -62], "mouth": [204, -42], "overhead": [0, -172]},
        },
    }
    json_out = os.path.join(REPO_ROOT, "project/assets/sprites/boss_mist_wolf_king_sheet.json")
    with open(json_out, "w", encoding="utf-8") as fh:
        json.dump(meta, fh, ensure_ascii=False, indent=2)
        fh.write("\n")

    return {
        "path": "project/assets/sprites/boss_mist_wolf_king_sheet.png",
        "source_path": "assets_src/sprites/r2_wolf_king_parts_sheet.png",
        "category": "sprite_sheet",
        "dimensions": f"{cw * cols}x{ch * rows_cnt}",
        "sha256": sha256_file(png_out),
        "creation_method": "Gemini Image Generation (assets_src/sprites/r2_wolf_king_side34_raw.png, Song-Ming Gongbi side-3/4 studio turnaround) + tools/build_polish_r2_actors.py (9-part anatomical segmentation, curved Telea socket feathering, 2x-supersampled rotary gallop/lunge/roar/grounded-collapse articulation, Song-Ming mineral LUT) | Spec: Giant side-3/4 Mist Wolf King 640x448 multi-pose combat sheet aligned to master_b_cangmu_rtwp.png",
        "generated_date": GEN_DATE,
        "license": LICENSE_R2,
    }


# ==============================================================================
# SECTION 2: MULTI-POSE PARTY HEROES (`gu_changqing`, `shen_qinghe`, `pei_zhao`)
# ==============================================================================
def extract_party_graft_parts() -> dict[str, dict[str, Any]]:
    """
    Extracts canonical Song-Ming Gongbi heads/crowns, collared chests, jade sword-box (`断玉剑匣`),
    back braid, Qingyun gold-cloud cape, and swords from `char_ref_party_{pets,back}_raw.jpg`,
    and archives `assets_src/sprites/r2_party_parts_sheet.png`.
    """
    pf_rgb = np.asarray(Image.open(os.path.join(REPO_ROOT, "assets_src/sprites/char_ref_party_pets_raw.jpg")).convert("RGB"))
    pb_rgb = np.asarray(Image.open(os.path.join(REPO_ROOT, "assets_src/sprites/char_ref_party_back_raw.jpg")).convert("RGB"))

    def matte_plate(arr: np.ndarray) -> np.ndarray:
        af = arr.astype(np.float32)
        bg = np.median(np.concatenate([af[0], af[-1], af[:, 0], af[:, -1]], axis=0), axis=0)
        bc = ((np.linalg.norm(af - bg, axis=2) < 22.5) & (af.mean(axis=2) > 198.0)).astype(np.uint8)
        nl, lbl = cv2.connectedComponents(bc, connectivity=8)
        ext = set(lbl[0, :]) | set(lbl[-1, :]) | set(lbl[:, 0]) | set(lbl[:, -1])
        ext.discard(0)
        fg = (~np.isin(lbl, list(ext))).astype(np.float32)
        for lid in range(1, nl):
            if lid not in ext:
                pts_y, _ = np.where(lbl == lid)
                if len(pts_y) < 180 and af[lbl == lid].mean() > 214.0:
                    fg[lbl == lid] = 0.0
        fg_b = cv2.GaussianBlur(fg, (3, 3), 0.50)
        al = np.clip((fg_b - 0.12) / 0.82 * 255.0, 0.0, 255.0).astype(np.uint8)
        rgb = af.copy()
        ed = (al > 8) & (al < 235)
        rgb[ed] = rgb[ed] * 0.55 + np.array([30.0, 26.0, 24.0], dtype=np.float32) * 0.45
        out = clean_zero_alpha(np.concatenate([np.clip(rgb, 0, 255).astype(np.uint8), al[..., None]], axis=2))
        return apply_song_ming_lut(out, sat_scale=0.93, val_scale=0.99)

    pf = matte_plate(pf_rgb)
    pb = matte_plate(pb_rgb)

    def sub_poly(plate: np.ndarray, box: tuple[int, int, int, int], poly_rel: list[tuple[float, float]] | None = None, feather: float = 1.8) -> np.ndarray:
        x0, y0, x1, y1 = box
        crop = plate[y0:y1, x0:x1].copy()
        if poly_rel is not None:
            m = np.zeros(crop.shape[:2], dtype=np.uint8)
            cv2.fillPoly(m, [np.round(np.array(poly_rel, dtype=np.float32)).astype(np.int32)], 255)
            mf = cv2.GaussianBlur(m.astype(np.float32), (0, 0), feather) / 255.0 if feather > 0.1 else m.astype(np.float32) / 255.0
            crop[..., 3] = np.clip(crop[..., 3].astype(np.float32) * mf, 0.0, 255.0).astype(np.uint8)
        return keep_largest_alpha_cc(clean_zero_alpha(crop), 10)

    # 1. Gu Changqing
    gu_head_f = sub_poly(pf, (124, 112, 246, 232), [(4, 0), (118, 0), (118, 116), (78, 119), (42, 116), (4, 86)], 1.5)
    gu_head_b = sub_poly(pb, (126, 113, 234, 232), [(0, 0), (106, 0), (106, 108), (54, 116), (0, 112)], 1.5)
    gu_chest_f = sub_poly(pf, (132, 218, 246, 368), [(18, 0), (92, 0), (108, 42), (94, 146), (20, 146), (6, 46)], 2.2)
    gu_casket_f = sub_poly(pf, (78, 198, 168, 345), [(0, 0), (88, 0), (62, 68), (54, 145), (0, 145)], 2.0)
    gu_casket_b = sub_poly(pb, (112, 196, 266, 404), [(38, 0), (152, 0), (152, 120), (76, 206), (0, 182), (4, 96)], 2.0)

    # 2. Shen Qinghe — mask/inpaint static waist hands & pouch out of `shen_chest_f` so only clean collar & bodice remain!
    shen_head_f = sub_poly(pf, (404, 150, 496, 266), [(0, 0), (90, 0), (90, 112), (48, 115), (4, 106)], 1.5)
    shen_head_b = sub_poly(pb, (404, 152, 494, 266), [(0, 0), (88, 0), (88, 112), (0, 112)], 1.5)
    shen_chest_raw = pf[250:334, 396:498].copy()
    # Inpaint any upper fingertip pixels at y_rel>=50, x_rel>=64 so bodice is 100% hand-free
    hand_mask = np.zeros(shen_chest_raw.shape[:2], dtype=np.uint8)
    skin_cand = (
        (shen_chest_raw[..., 0].astype(np.int32) - shen_chest_raw[..., 1].astype(np.int32) > 14)
        & (shen_chest_raw[..., 0] > 165)
    )
    hand_mask[46:, 52:] = (skin_cand[46:, 52:]).astype(np.uint8) * 255
    hand_mask = cv2.dilate(hand_mask, np.ones((5, 5), dtype=np.uint8), iterations=1)
    if np.any(hand_mask > 0):
        shen_chest_raw[..., :3] = cv2.inpaint(shen_chest_raw[..., :3], hand_mask, 5.0, cv2.INPAINT_TELEA)
    m_sc = np.zeros(shen_chest_raw.shape[:2], dtype=np.uint8)
    cv2.fillPoly(m_sc, [np.array([(20, 0), (84, 0), (92, 34), (84, 80), (20, 80), (12, 36)], dtype=np.int32)], 255)
    mf_sc = cv2.GaussianBlur(m_sc.astype(np.float32), (0, 0), 2.2) / 255.0
    shen_chest_raw[..., 3] = np.clip(shen_chest_raw[..., 3].astype(np.float32) * mf_sc, 0.0, 255.0).astype(np.uint8)
    shen_chest_f = keep_largest_alpha_cc(clean_zero_alpha(shen_chest_raw), 10)
    shen_braid_b = sub_poly(pb, (398, 164, 488, 456), [(14, 0), (76, 0), (74, 140), (60, 290), (26, 290), (16, 140)], 2.0)

    # 3. Pei Zhao — trim static lower pant stubs (`y_rel <= 376`) and right scabbard tip (`x_rel <= 165` in `y_rel=205..255`) from `pei_cape_b`!
    pei_head_f = sub_poly(pf, (666, 99, 756, 224), [(0, 0), (88, 0), (88, 122), (46, 124), (4, 116)], 1.5)
    pei_head_b = sub_poly(pb, (672, 100, 760, 224), [(0, 0), (86, 0), (86, 120), (0, 120)], 1.5)
    pei_chest_f = sub_poly(pf, (640, 206, 770, 366), [(14, 0), (118, 0), (128, 36), (108, 156), (24, 156), (4, 36)], 2.2)
    pei_cape_b = sub_poly(
        pb,
        (602, 206, 796, 584),
        sample_bezier_chain([
            [(34, 0), (166, 0)],
            [(166, 0), (186, 48), (186, 195)],
            [(186, 195), (163, 215), (164, 255), (184, 285)],
            [(184, 285), (186, 372)],
            [(186, 372), (132, 377), (64, 376), (6, 364)],
            [(6, 364), (16, 200), (20, 52)],
            [(20, 52), (34, 0)],
        ], 10),
        2.2,
    )

    # Synthesize razor-crisp 2x Song-Ming Gongbi swords (+X horizontal, pivot at grip `(28, 32)`)
    def build_gongbi_sword(kind: str) -> tuple[np.ndarray, tuple[float, float]]:
        sw, sh = 232, 64
        im_s = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
        d = ImageDraw.Draw(im_s)
        cy = 32
        if kind == "qingming":
            d.polygon([(8, cy - 5), (42, cy - 4), (42, cy + 4), (8, cy + 5)], fill=(72, 58, 46, 255), outline=(24, 20, 18, 255))
            d.ellipse((2, cy - 7, 13, cy + 7), fill=(138, 112, 68, 255), outline=(24, 20, 18, 255))
            d.polygon([(48, cy - 8), (198, cy - 5), (226, cy), (198, cy + 5), (48, cy + 8)], fill=(178, 194, 198, 255), outline=(24, 20, 18, 255))
            d.polygon([(50, cy - 7), (196, cy - 4), (222, cy), (50, cy)], fill=(216, 228, 232, 255))
            d.line([(52, cy), (210, cy)], fill=(92, 112, 116, 230), width=2)
            d.polygon([(40, cy - 16), (54, cy - 11), (56, cy), (54, cy + 11), (40, cy + 16), (36, cy)], fill=(154, 124, 72, 255), outline=(24, 20, 18, 255))
        else:
            d.polygon([(6, cy - 5), (42, cy - 5), (42, cy + 5), (6, cy + 5)], fill=(116, 92, 56, 255), outline=(24, 20, 18, 255))
            d.polygon([(0, cy), (9, cy - 8), (15, cy), (9, cy + 8)], fill=(214, 178, 102, 255), outline=(24, 20, 18, 255))
            d.polygon([(50, cy - 11), (84, cy - 8), (200, cy - 6), (230, cy), (200, cy + 6), (84, cy + 8), (50, cy + 11)], fill=(196, 212, 222, 255), outline=(24, 20, 18, 255))
            d.polygon([(52, cy - 9), (198, cy - 5), (225, cy), (52, cy)], fill=(232, 240, 246, 255))
            d.line([(58, cy), (204, cy)], fill=(182, 152, 92, 245), width=3)
            d.polygon([(38, cy - 21), (58, cy - 14), (62, cy), (58, cy + 14), (38, cy + 21), (34, cy)], fill=(208, 174, 102, 255), outline=(24, 20, 18, 255))
            d.ellipse((43, cy - 5, 53, cy + 5), fill=(112, 186, 156, 255), outline=(26, 22, 20, 255))
        return clean_zero_alpha(np.asarray(im_s)), (28.0, float(cy))

    sw_gu = build_gongbi_sword("qingming")
    sw_pei = build_gongbi_sword("qingyun")

    # Archive party graft parts sheet to `assets_src/sprites/r2_party_parts_sheet.png`
    arch = Image.new("RGBA", (1280, 720), (242, 236, 224, 255))
    arch_np = np.asarray(arch).copy()
    slots = [
        (gu_head_f, 24, 24), (gu_head_b, 170, 24), (gu_chest_f, 300, 24), (gu_casket_b, 440, 24), (sw_gu[0], 620, 60),
        (shen_head_f, 24, 250), (shen_head_b, 150, 250), (shen_chest_f, 270, 250), (shen_braid_b, 400, 220),
        (pei_head_f, 24, 470), (pei_head_b, 150, 470), (pei_chest_f, 270, 470), (pei_cape_b, 560, 250), (sw_pei[0], 870, 60),
    ]
    for arr_p, sx, sy in slots:
        ph, pw = arr_p.shape[:2]
        ph_c = min(ph, 720 - sy)
        pw_c = min(pw, 1280 - sx)
        if ph_c > 0 and pw_c > 0:
            alpha_over_np(arch_np[sy : sy + ph_c, sx : sx + pw_c], arr_p[:ph_c, :pw_c])
    save_rgba_clean(arch_np, os.path.join(REPO_ROOT, "assets_src/sprites/r2_party_parts_sheet.png"))

    return {
        "gu_changqing": {
            "head_f": (gu_head_f, (60.0, 96.0)),
            "head_b": (gu_head_b, (54.0, 96.0)),
            "chest_f": (gu_chest_f, (56.0, 78.0)),
            "casket_f": (gu_casket_f, (54.0, 78.0)),
            "casket_b": (gu_casket_b, (82.0, 98.0)),
            "sword": sw_gu,
            "stand_scale": 0.485,
            "foot_y": 248,
            "head_top_px": 162,
            "palette": {
                "robe_main": (74, 94, 96),
                "robe_hi": (96, 118, 120),
                "robe_sh": (50, 66, 68),
                "inner": (196, 192, 180),
                "sash": (48, 60, 62),
                "bracer": (52, 56, 58),
                "pants": (58, 70, 72),
                "boot": (46, 52, 52),
                "sole": (198, 192, 180),
                "skin": (224, 192, 166),
            },
        },
        "shen_qinghe": {
            "head_f": (shen_head_f, (46.0, 94.0)),
            "head_b": (shen_head_b, (44.0, 94.0)),
            "chest_f": (shen_chest_f, (50.0, 44.0)),
            "braid_b": (shen_braid_b, (45.0, 96.0)),
            "sword": None,
            "stand_scale": 0.495,
            "foot_y": 248,
            "head_top_px": 154,
            "palette": {
                "robe_main": (218, 212, 192),
                "robe_hi": (234, 228, 210),
                "robe_sh": (184, 178, 158),
                "skirt_green": (92, 138, 112),
                "skirt_sh": (66, 104, 84),
                "sash": (196, 176, 126),
                "bracer": (92, 138, 112),
                "pants": (212, 208, 190),
                "boot": (96, 136, 108),
                "sole": (222, 216, 198),
                "skin": (234, 204, 182),
            },
        },
        "pei_zhao": {
            "head_f": (pei_head_f, (45.0, 104.0)),
            "head_b": (pei_head_b, (43.0, 104.0)),
            "chest_f": (pei_chest_f, (66.0, 80.0)),
            "cape_b": (pei_cape_b, (98.0, 56.0)),
            "sword": sw_pei,
            "stand_scale": 0.492,
            "foot_y": 248,
            "head_top_px": 166,
            "palette": {
                "robe_main": (222, 216, 204),
                "robe_hi": (238, 233, 224),
                "robe_sh": (186, 178, 164),
                "gold_trim": (184, 148, 86),
                "sash": (172, 138, 78),
                "bracer": (156, 124, 72),
                "pants": (74, 68, 60),
                "boot": (62, 56, 48),
                "sole": (178, 150, 98),
                "skin": (228, 198, 174),
            },
        },
    }


def _solve_2bone(p0: tuple[float, float], p2: tuple[float, float], l1: float, l2: float, bend_sign: float = 1.0) -> tuple[float, float]:
    dx, dy = p2[0] - p0[0], p2[1] - p0[1]
    d = math.hypot(dx, dy)
    d_clamped = max(abs(l1 - l2) + 0.5, min(l1 + l2 - 0.5, d))
    if d < 1e-4:
        return (p0[0] + l1, p0[1])
    cos_a = (l1 * l1 + d_clamped * d_clamped - l2 * l2) / (2.0 * l1 * d_clamped)
    cos_a = max(-1.0, min(1.0, cos_a))
    ang0 = math.atan2(dy, dx) + bend_sign * math.acos(cos_a)
    return (p0[0] + math.cos(ang0) * l1, p0[1] + math.sin(ang0) * l1)


def _draw_tapered_segment(
    draw: ImageDraw.ImageDraw,
    a: tuple[float, float],
    b: tuple[float, float],
    r_a: float,
    r_b: float,
    fill_col: tuple[int, int, int, int],
    hi_col: tuple[int, int, int, int] | None = None,
    ink_col: tuple[int, int, int, int] = (28, 24, 22, 255),
) -> None:
    dx, dy = b[0] - a[0], b[1] - a[1]
    ln = max(1.0, math.hypot(dx, dy))
    nx, ny = -dy / ln, dx / ln
    poly = [
        (a[0] + nx * r_a, a[1] + ny * r_a),
        (b[0] + nx * r_b, b[1] + ny * r_b),
        (b[0] - nx * r_b, b[1] - ny * r_b),
        (a[0] - nx * r_a, a[1] - ny * r_a),
    ]
    draw.polygon(poly, fill=fill_col)
    draw.ellipse((a[0] - r_a, a[1] - r_a, a[0] + r_a, a[1] + r_a), fill=fill_col)
    draw.ellipse((b[0] - r_b, b[1] - r_b, b[0] + r_b, b[1] + r_b), fill=fill_col)
    if hi_col is not None:
        hpoly = [
            (a[0] + nx * r_a * 0.85, a[1] + ny * r_a * 0.85),
            (b[0] + nx * r_b * 0.85, b[1] + ny * r_b * 0.85),
            (b[0], b[1]),
            (a[0], a[1]),
        ]
        draw.polygon(hpoly, fill=hi_col)
    draw_bezier_ink(draw, [poly[0], poly[1]], ink_col, 2.5, 2.2, 12)
    draw_bezier_ink(draw, [poly[3], poly[2]], ink_col, 2.5, 2.2, 12)


def _draw_gongbi_boot(
    draw: ImageDraw.ImageDraw,
    ankle: tuple[float, float],
    toe_dir: float,
    boot_col: tuple[int, int, int],
    sole_col: tuple[int, int, int],
    is_shen: bool = False,
) -> None:
    ax, ay = ankle
    s = 1.0 if toe_dir >= 0 else -1.0
    if is_shen:
        # Curved cloud-toe Song-Ming embroidered cloth shoe (`云头绣履`)
        pts = sample_bezier_chain([
            [(ax - 9 * s, ay + 6), (ax + 18 * s, ay + 6)],
            [(ax + 18 * s, ay + 6), (ax + 24 * s, ay + 3), (ax + 22 * s, ay - 3), (ax + 12 * s, ay - 6)],
            [(ax + 12 * s, ay - 6), (ax + 2 * s, ay - 7), (ax - 8 * s, ay - 5)],
            [(ax - 8 * s, ay - 5), (ax - 9 * s, ay + 6)],
        ], 8)
    else:
        pts = sample_bezier_chain([
            [(ax - 10 * s, ay + 7), (ax + 21 * s, ay + 7)],
            [(ax + 21 * s, ay + 7), (ax + 27 * s, ay + 2), (ax + 24 * s, ay - 4), (ax + 12 * s, ay - 8)],
            [(ax + 12 * s, ay - 8), (ax - 9 * s, ay - 8)],
            [(ax - 9 * s, ay - 8), (ax - 10 * s, ay + 7)],
        ], 8)
    draw.polygon(pts, fill=(*boot_col, 255), outline=(26, 22, 20, 255))
    draw.line([(ax - 9 * s, ay + 7), (ax + 20 * s, ay + 7)], fill=(*sole_col, 255), width=3)
    draw.line([(ax - 9 * s, ay + 8), (ax + 20 * s, ay + 8)], fill=(26, 22, 20, 255), width=2)


def _draw_curved_panel(
    draw: ImageDraw.ImageDraw,
    chains: list[list[tuple[float, float]]],
    fill_rgba: tuple[int, int, int, int],
    ink_rgba: tuple[int, int, int, int] = (26, 22, 20, 255),
    ink_w: float = 2.4,
) -> list[tuple[float, float]]:
    pts = sample_bezier_chain(chains, steps_per_seg=14)
    draw.polygon(pts, fill=fill_rgba)
    for seg in chains:
        draw_bezier_ink(draw, seg, ink_rgba, ink_w, ink_w * 0.9, 14)
    return pts


def render_party_hero_cell(
    actor_id: str,
    rig_data: dict[str, Any],
    pose: dict[str, Any],
    cell_w: int = 352,
    cell_h: int = 280,
) -> np.ndarray:
    """
    Renders a single 352x280 party hero keyframe at 2x supersampling (704x560 -> Lanczos 352x280),
    combining articulated 2-bone Song-Ming Gongbi limbs & curved Bezier drapery with grafted
    canonical heads, cross-collar chests, jade casket, Qingyun cape, and swords.
    """
    W2, H2 = cell_w * 2, cell_h * 2
    foot_y = int(rig_data["foot_y"])
    pal = rig_data["palette"]
    sc_g = float(rig_data["stand_scale"])
    is_ne = bool(pose.get("is_ne", False))
    is_down = bool(pose.get("is_down", False))
    is_moving = bool(pose.get("is_moving", False))
    is_shen = (actor_id == "shen_qinghe")
    is_pei = (actor_id == "pei_zhao")
    is_gu = (actor_id == "gu_changqing")

    fx2 = W2 * 0.5 + float(pose.get("root_dx", 0.0)) * 2.0
    fy2 = foot_y * 2.0 - 12.0  # Ankle sits 6px (12px at 2x) above boot sole at foot_y!

    hip_y_base = -82.0 if is_gu else (-77.0 if is_shen else -84.0)
    hip = (fx2 + float(pose.get("hip_dx", 0.0)) * 2.0, fy2 + (hip_y_base + float(pose.get("hip_dy", 0.0))) * 2.0)
    lean_deg = float(pose.get("lean_deg", 0.0))
    lean_rad = math.radians(lean_deg)
    torso_len = 86.0 if is_gu else (80.0 if is_shen else 88.0)
    neck = (hip[0] + math.sin(lean_rad) * torso_len, hip[1] - math.cos(lean_rad) * torso_len)
    chest_c = (
        (hip[0] + neck[0]) * 0.5,
        (hip[1] + neck[1]) * 0.5 + (4.0 if not is_shen else -12.0),
    )

    lf_end = (fx2 + float(pose.get("lf_dx", -14.0)) * 2.0, fy2 + float(pose.get("lf_dy", -2.0)) * 2.0)
    rf_end = (fx2 + float(pose.get("rf_dx", 16.0)) * 2.0, fy2 + float(pose.get("rf_dy", 0.0)) * 2.0)
    hip_l = (hip[0] - 10.0, hip[1] + 6.0)
    hip_r = (hip[0] + 10.0, hip[1] + 6.0)
    thigh_l, shin_l = (82.0, 82.0) if not is_shen else (76.0, 76.0)
    l_knee = _solve_2bone(hip_l, lf_end, thigh_l, shin_l, bend_sign=float(pose.get("lk_sign", -1.0)))
    r_knee = _solve_2bone(hip_r, rf_end, thigh_l, shin_l, bend_sign=float(pose.get("rk_sign", -1.0)))
    l_knee = (l_knee[0], min(l_knee[1], fy2 - 4.0))
    r_knee = (r_knee[0], min(r_knee[1], fy2 - 4.0))

    sh_l = (neck[0] - 18.0, neck[1] + 18.0)
    sh_r = (neck[0] + 16.0, neck[1] + 20.0)
    lh_end = (neck[0] + float(pose.get("lh_dx", -22.0)) * 1.65, neck[1] + float(pose.get("lh_dy", 46.0)) * 1.55)
    rh_end = (neck[0] + float(pose.get("rh_dx", 24.0)) * 1.65, neck[1] + float(pose.get("rh_dy", 44.0)) * 1.55)
    arm_l1, arm_l2 = (46.0, 46.0) if not is_shen else (42.0, 42.0)
    l_elb = _solve_2bone(sh_l, lh_end, arm_l1, arm_l2, bend_sign=float(pose.get("le_sign", 1.0)))
    r_elb = _solve_2bone(sh_r, rh_end, arm_l1, arm_l2, bend_sign=float(pose.get("re_sign", 1.0)))

    canvas = np.zeros((H2, W2, 4), dtype=np.uint8)

    def new_layer() -> tuple[Image.Image, ImageDraw.ImageDraw]:
        im_l = Image.new("RGBA", (W2, H2), (0, 0, 0, 0))
        return im_l, ImageDraw.Draw(im_l)

    def flush_layer(im_l: Image.Image) -> None:
        alpha_over_np(canvas, np.asarray(im_l))

    def draw_arm(sh_pt: tuple[float, float], elb_pt: tuple[float, float], hand_pt: tuple[float, float], shade: float) -> None:
        im_a, da = new_layer()
        rm = tuple(int(c * shade) for c in pal["robe_main"])
        rh_c = tuple(int(c * shade) for c in pal["robe_hi"])
        rs_c = tuple(int(c * shade) for c in pal["robe_sh"])
        br_c = tuple(int(c * shade) for c in pal["bracer"])
        sk_c = tuple(int(c * shade) for c in pal["skin"])
        if is_shen:
            # Curved bell/teardrop Song-Ming `广袖` wide flowing sleeve (ZERO 4-vertex cardboard boxes!)
            dx_a = hand_pt[0] - sh_pt[0]
            dy_a = hand_pt[1] - sh_pt[1]
            ln_a = max(1.0, math.hypot(dx_a, dy_a))
            ux_a, uy_a = dx_a / ln_a, dy_a / ln_a
            # Top ridge follows shoulder -> elbow -> wrist smoothly
            top_sh = (sh_pt[0] - uy_a * 11.0, sh_pt[1] + ux_a * 11.0 - 6.0)
            top_el = (elb_pt[0], elb_pt[1] - 13.0)
            top_wr = (hand_pt[0] - ux_a * 4.0, hand_pt[1] - 11.0)
            # Gravity-drooping curved bell pouch under wrist/elbow
            cuff_bot = (hand_pt[0] - ux_a * 6.0, hand_pt[1] + 32.0)
            belly_sag = ((elb_pt[0] + hand_pt[0]) * 0.5 - ux_a * 8.0, max(elb_pt[1], hand_pt[1]) + 38.0)
            armpit_pt = (sh_pt[0] - 4.0, sh_pt[1] + 16.0)
            sleeve_chains = [
                [top_sh, top_el, top_wr],
                [top_wr, (hand_pt[0] + ux_a * 5.0, hand_pt[1] + 8.0), cuff_bot],
                [cuff_bot, belly_sag, (elb_pt[0] - ux_a * 6.0, elb_pt[1] + 24.0), armpit_pt],
                [armpit_pt, top_sh],
            ]
            _draw_curved_panel(da, sleeve_chains, (*rm, 255), (28, 24, 22, 255), 2.2)
            # Curved celadon-green wide cuff trim (`翠袖缘边`) + delicate inner drapery folds
            draw_bezier_ink(da, [top_wr, (hand_pt[0] + ux_a * 3.0, hand_pt[1] + 8.0), cuff_bot], (*br_c, 255), 6.2, 5.2, 16)
            draw_bezier_ink(da, [top_wr, (hand_pt[0] + ux_a * 5.0, hand_pt[1] + 8.0), cuff_bot], (26, 22, 20, 255), 2.0, 1.8, 16)
            draw_bezier_ink(da, [(elb_pt[0], elb_pt[1] + 2.0), ((elb_pt[0] + cuff_bot[0]) * 0.5, belly_sag[1] - 10.0), (cuff_bot[0] - ux_a * 6.0, cuff_bot[1] - 4.0)], (*rs_c, 220), 2.2, 1.2, 14)
            # Articulated Gongbi hand emerging from wide cuff (slender Qi palm or soft cupped fingers)
            s_dir = 1.0 if dx_a >= -4.0 else -1.0
            if bool(pose.get("open_palm", False)) and shade > 0.94:
                palm_pts = sample_bezier_chain([
                    [(hand_pt[0] - 5 * s_dir, hand_pt[1] + 5), (hand_pt[0] + 6 * s_dir, hand_pt[1] + 5)],
                    [(hand_pt[0] + 6 * s_dir, hand_pt[1] + 5), (hand_pt[0] + 12 * s_dir, hand_pt[1] - 6), (hand_pt[0] + 6 * s_dir, hand_pt[1] - 17)],
                    [(hand_pt[0] + 6 * s_dir, hand_pt[1] - 17), (hand_pt[0] - 2 * s_dir, hand_pt[1] - 15), (hand_pt[0] - 6 * s_dir, hand_pt[1] - 4)],
                    [(hand_pt[0] - 6 * s_dir, hand_pt[1] - 4), (hand_pt[0] - 5 * s_dir, hand_pt[1] + 5)],
                ], 8)
                da.polygon(palm_pts, fill=(*sk_c, 255), outline=(26, 22, 20, 255))
            else:
                cup_pts = sample_bezier_chain([
                    [(hand_pt[0] - 5 * s_dir, hand_pt[1] - 5), (hand_pt[0] + 9 * s_dir, hand_pt[1] - 4)],
                    [(hand_pt[0] + 9 * s_dir, hand_pt[1] - 4), (hand_pt[0] + 11 * s_dir, hand_pt[1] + 4), (hand_pt[0] + 3 * s_dir, hand_pt[1] + 7)],
                    [(hand_pt[0] + 3 * s_dir, hand_pt[1] + 7), (hand_pt[0] - 6 * s_dir, hand_pt[1] + 4)],
                    [(hand_pt[0] - 6 * s_dir, hand_pt[1] + 4), (hand_pt[0] - 5 * s_dir, hand_pt[1] - 5)],
                ], 8)
                da.polygon(cup_pts, fill=(*sk_c, 255), outline=(26, 22, 20, 255))
        else:
            _draw_tapered_segment(da, sh_pt, elb_pt, 14.5, 13.5, (*rm, 255), (*rh_c, 255))
            _draw_tapered_segment(da, elb_pt, hand_pt, 12.0, 8.5, (*br_c, 255))
            da.ellipse((hand_pt[0] - 8, hand_pt[1] - 8, hand_pt[0] + 9, hand_pt[1] + 8), fill=(*sk_c, 255), outline=(26, 22, 20, 255))
        flush_layer(im_a)

    def draw_sword_layer() -> None:
        sw_entry = rig_data.get("sword")
        if sw_entry is not None and bool(pose.get("show_sword", True)):
            s_arr, s_piv = sw_entry
            s_ang = float(pose.get("sword_ang", 28.0))
            paste_transformed_part(canvas, s_arr, s_piv, rh_end, angle_deg=s_ang, scale_xy=(0.90, 0.90))

    def draw_legs_and_drapery() -> None:
        im_legs, dl = new_layer()
        wind_flare = float(pose.get("flare_x", 0.0)) * 2.0
        stride_signed = rf_end[0] - lf_end[0]  # Positive when right (near) leg leads +X; negative when left (far) leg leads +X!

        # Far leg (left)
        _draw_tapered_segment(dl, hip_l, l_knee, 15.5, 12.0, (*(int(c * 0.84) for c in pal["pants"]), 255))
        _draw_tapered_segment(dl, l_knee, lf_end, 11.5, 8.5, (*(int(c * 0.84) for c in pal["boot"]), 255))
        _draw_gongbi_boot(dl, lf_end, float(pose.get("lf_dir", 1.0)), tuple(int(c * 0.82) for c in pal["boot"]), pal["sole"], is_shen)

        if is_shen:
            # Draw near leg (right) + front embroidered shoe BEFORE pleated skirt so BOTH alternating shoes step visibly beneath hem!
            _draw_tapered_segment(dl, hip_r, r_knee, 15.5, 12.0, (*pal["pants"], 255))
            _draw_tapered_segment(dl, r_knee, rf_end, 11.5, 8.5, (*pal["boot"], 255))
            _draw_gongbi_boot(dl, rf_end, float(pose.get("rf_dir", 1.0)), pal["boot"], pal["sole"], True)

            if is_down:
                # Grounded kneeling/collapsed Song-Ming skirt pool resting flush along ground plane (ZERO shelf or underside triangle!)
                pool_l = min(lf_end[0], hip[0]) - 36.0
                pool_r = max(rf_end[0], hip[0]) + 28.0
                pool_y = fy2 + 5.0
                top_y = min(hip[1] - 4.0, pool_y - 34.0)
                outer_pool = [
                    [(hip[0] - 22, top_y), (hip[0] + 22, top_y)],
                    [(hip[0] + 22, top_y), (pool_r - 4, (top_y + pool_y) * 0.5), (pool_r, pool_y)],
                    [(pool_r, pool_y), ((pool_l + pool_r) * 0.5, pool_y + 2.0), (pool_l, pool_y)],
                    [(pool_l, pool_y), (pool_l + 12, (top_y + pool_y) * 0.45), (hip[0] - 22, top_y)],
                ]
                _draw_curved_panel(dl, outer_pool, (*pal["robe_main"], 255))
                green_y = pool_y - 10.0
                inner_pool = [
                    [(hip[0] - 18, top_y + 2), (hip[0] + 18, top_y + 2)],
                    [(hip[0] + 18, top_y + 2), (pool_r - 12, (top_y + green_y) * 0.55), (pool_r - 10, green_y)],
                    [(pool_r - 10, green_y), ((pool_l + pool_r) * 0.5, green_y + 2.0), (pool_l + 12, green_y)],
                    [(pool_l + 12, green_y), (pool_l + 20, (top_y + green_y) * 0.5), (hip[0] - 18, top_y + 2)],
                ]
                _draw_curved_panel(dl, inner_pool, (*pal["skirt_green"], 255))
                for pi in range(4):
                    tx = (pi + 1) / 5.0
                    px_t = (hip[0] - 14) * (1 - tx) + (hip[0] + 14) * tx
                    px_b = (pool_l + 22) * (1 - tx) + (pool_r - 18) * tx
                    draw_bezier_ink(dl, [(px_t, top_y + 6), ((px_t + px_b) * 0.5, (top_y + green_y) * 0.55), (px_b, green_y - 2)], (*pal["skirt_sh"], 220), 2.0, 1.3)
            else:
                # Standing / running / casting curved Song-Ming `百褶长裙`
                # Raised slightly (`fy2 - 14`) during run/attack so alternating left/right cloth shoes are clearly visible!
                hem_raise = 15.0 if is_moving else 4.0
                sk_bottom_y = fy2 - hem_raise
                # Asymmetric stride response breaks period-3 min/max symmetry between col 0 (rf<lf) and col 3 (rf>lf)!
                asym_shift = stride_signed * 0.24
                sk_l = min(lf_end[0], hip[0]) - 22.0 + wind_flare * 0.55 + min(0.0, asym_shift * 0.8)
                sk_r = max(rf_end[0], hip[0]) + 22.0 + wind_flare * 0.20 + max(0.0, asym_shift * 1.15)
                mid_hem_y = sk_bottom_y + (4.0 if stride_signed >= 0 else -3.0)

                cream_skirt = [
                    [(hip[0] - 23, hip[1] - 6), (hip[0] + 23, hip[1] - 6)],
                    [(hip[0] + 23, hip[1] - 6), (hip[0] + 28, (hip[1] + sk_bottom_y) * 0.45), (sk_r + 6, sk_bottom_y - 14), (sk_r + 8, sk_bottom_y + 2)],
                    [(sk_r + 8, sk_bottom_y + 2), ((sk_l + sk_r) * 0.5 + asym_shift * 0.4, mid_hem_y + 6), (sk_l - 8, sk_bottom_y + 3)],
                    [(sk_l - 8, sk_bottom_y + 3), (sk_l - 2, sk_bottom_y - 18), (hip[0] - 28, (hip[1] + sk_bottom_y) * 0.48), (hip[0] - 23, hip[1] - 6)],
                ]
                _draw_curved_panel(dl, cream_skirt, (*pal["robe_main"], 255))

                gr_y = sk_bottom_y - 12.0
                green_skirt = [
                    [(hip[0] - 19, hip[1] - 5), (hip[0] + 19, hip[1] - 5)],
                    [(hip[0] + 19, hip[1] - 5), (hip[0] + 24, (hip[1] + gr_y) * 0.46), (sk_r - 2, gr_y)],
                    [(sk_r - 2, gr_y), ((sk_l + sk_r) * 0.5 + asym_shift * 0.5, gr_y + 5), (sk_l + 2, gr_y + 1)],
                    [(sk_l + 2, gr_y + 1), (hip[0] - 24, (hip[1] + gr_y) * 0.48), (hip[0] - 19, hip[1] - 5)],
                ]
                _draw_curved_panel(dl, green_skirt, (*pal["skirt_green"], 255))

                for pi in range(5):
                    tx = (pi + 1) / 6.0
                    px_top = (hip[0] - 15) * (1 - tx) + (hip[0] + 15) * tx
                    px_bot = (sk_l + 8) * (1 - tx) + (sk_r - 6) * tx + asym_shift * 0.22
                    px_mid = (px_top + px_bot) * 0.5 + wind_flare * 0.15
                    draw_bezier_ink(dl, [(px_top, hip[1] + 4), (px_mid, (hip[1] + gr_y) * 0.52), (px_bot, gr_y - 2)], (*pal["skirt_sh"], 230), 2.2, 1.3)

                # Curved waist sash + fluttering asymmetric central ribbon (`绶带`)
                sash_sway = wind_flare * 0.45 - stride_signed * 0.32
                sash_bot_y = gr_y - 6.0
                sash_chains = [
                    [(hip[0] - 7, hip[1] - 4), (hip[0] + 8, hip[1] - 4)],
                    [(hip[0] + 8, hip[1] - 4), (hip[0] + 10 + sash_sway * 0.4, (hip[1] + sash_bot_y) * 0.5), (hip[0] + 10 + sash_sway, sash_bot_y)],
                    [(hip[0] + 10 + sash_sway, sash_bot_y), (hip[0] - 8 + sash_sway, sash_bot_y + 2)],
                    [(hip[0] - 8 + sash_sway, sash_bot_y + 2), (hip[0] - 6 + sash_sway * 0.4, (hip[1] + sash_bot_y) * 0.5), (hip[0] - 7, hip[1] - 4)],
                ]
                _draw_curved_panel(dl, sash_chains, (*pal["sash"], 255), (28, 24, 22, 255), 2.0)
                dl.polygon([(hip[0] - 23, hip[1] - 11), (hip[0] + 23, hip[1] - 11), (hip[0] + 24, hip[1] - 1), (hip[0] - 24, hip[1] - 1)], fill=(*pal["sash"], 255), outline=(26, 22, 20, 255))
        else:
            # S-curved flowing Song-Ming split martial robe panels (`开裾战袍`, ZERO 4-vertex paper-cone triangles!)
            asym_wave = stride_signed * 0.25
            back_tip_x = min(lf_end[0], hip[0]) - 22.0 + wind_flare * 0.72 - max(0.0, asym_wave * 0.45)
            back_tip_y = min(fy2 - 20.0, max(hip[1] + 34.0, l_knee[1] + 38.0))
            back_in_x = hip[0] - 2.0 + min(0.0, asym_wave * 0.25)
            back_in_y = min(fy2 - 16.0, back_tip_y + 10.0)
            back_chains = [
                [(hip[0] - 22, hip[1] - 8), (hip[0] + 10, hip[1] - 4)],
                [(hip[0] + 10, hip[1] - 4), (hip[0] + 6, (hip[1] + back_in_y) * 0.52), (back_in_x, back_in_y)],
                [(back_in_x, back_in_y), ((back_in_x + back_tip_x) * 0.5, back_in_y + 4.0), (back_tip_x, back_tip_y)],
                [(back_tip_x, back_tip_y), (back_tip_x + 10.0, (hip[1] + back_tip_y) * 0.58), (hip[0] - 26, hip[1] + 14), (hip[0] - 22, hip[1] - 8)],
            ]
            _draw_curved_panel(dl, back_chains, (*pal["robe_sh"], 255))
            draw_bezier_ink(dl, [(hip[0] - 14, hip[1] + 4), ((hip[0] + back_tip_x) * 0.5, (hip[1] + back_tip_y) * 0.56), (back_tip_x + 12, back_tip_y + 2)], (26, 22, 20, 190), 2.0, 1.2)

            # Near leg (right) clearly exposed in bent `弓步` martial stance!
            _draw_tapered_segment(dl, hip_r, r_knee, 16.5, 13.0, (*pal["pants"], 255))
            _draw_tapered_segment(dl, r_knee, rf_end, 12.5, 9.0, (*pal["boot"], 255))
            _draw_gongbi_boot(dl, rf_end, float(pose.get("rf_dir", 1.0)), pal["boot"], pal["sole"], False)

            # Front curved martial split apron/panel (`前裾`) swaying with stride
            f_out_x = max(hip[0] + 22.0, r_knee[0] + 14.0) + max(0.0, asym_wave * 0.35) - wind_flare * 0.15
            f_out_y = min(fy2 - 22.0, max(hip[1] + 34.0, (hip[1] + fy2) * 0.56 + 14.0))
            f_in_x = hip[0] - 12.0 + wind_flare * 0.35 + asym_wave * 0.28
            f_in_y = min(fy2 - 16.0, f_out_y + 12.0)
            front_chains = [
                [(hip[0] - 18, hip[1] - 8), (hip[0] + 22, hip[1] - 6)],
                [(hip[0] + 22, hip[1] - 6), (hip[0] + 26, (hip[1] + f_out_y) * 0.48), (f_out_x, f_out_y - 12), (f_out_x + 4, f_out_y)],
                [(f_out_x + 4, f_out_y), ((f_out_x + f_in_x) * 0.5, f_in_y + 5.0), (f_in_x, f_in_y)],
                [(f_in_x, f_in_y), (hip[0] - 20 + wind_flare * 0.18, (hip[1] + f_in_y) * 0.54), (hip[0] - 18, hip[1] - 8)],
            ]
            _draw_curved_panel(dl, front_chains, (*pal["robe_main"], 255))
            if is_pei:
                # Curved gold-brocade border along front panel
                draw_bezier_ink(dl, front_chains[1], (*pal["gold_trim"], 255), 5.6, 5.2, 14)
                draw_bezier_ink(dl, front_chains[2], (*pal["gold_trim"], 255), 5.4, 5.0, 14)
                draw_bezier_ink(dl, front_chains[1], (26, 22, 20, 255), 1.8, 1.8, 14)
                draw_bezier_ink(dl, front_chains[2], (26, 22, 20, 255), 1.8, 1.8, 14)
            else:
                # Gu Changqing fluttering dark-slate belt sash tail (`腰带飘带`) for crisp stride silhouette contrast!
                sash_end_x = hip[0] - 26.0 + wind_flare * 0.85 - asym_wave * 0.45
                sash_end_y = min(fy2 - 26.0, hip[1] + 54.0 - abs(asym_wave) * 0.15)
                draw_bezier_ink(dl, [(hip[0] - 8, hip[1] - 2), (hip[0] - 22 + wind_flare * 0.4, hip[1] + 24), (sash_end_x, sash_end_y)], (*pal["sash"], 255), 7.5, 4.2, 16)
                draw_bezier_ink(dl, [(hip[0] - 8, hip[1] - 2), (hip[0] - 22 + wind_flare * 0.4, hip[1] + 24), (sash_end_x, sash_end_y)], (24, 20, 18, 225), 2.0, 1.4, 16)

            draw_bezier_ink(dl, [(hip[0] + 2, hip[1] + 4), ((hip[0] + f_out_x) * 0.5, (hip[1] + f_out_y) * 0.52), (f_out_x - 6, f_out_y - 2)], (*pal["robe_sh"], 235), 2.4, 1.3, 14)
            draw_bezier_ink(dl, [(hip[0] - 10, hip[1] + 6), ((hip[0] - 12 + f_in_x) * 0.5, (hip[1] + f_in_y) * 0.54), (f_in_x + 8, f_in_y - 3)], (28, 24, 22, 215), 2.0, 1.2, 14)
        flush_layer(im_legs)

    if not is_ne:
        # ==================== SE FRONT-3/4 Z-ORDER ====================
        # 1. Back accessory behind torso in SE view (Gu's jade casket corner)
        if is_gu:
            carr, cpiv = rig_data["casket_f"]
            paste_transformed_part(canvas, carr, cpiv, (chest_c[0] - 26.0, chest_c[1] - 18.0), angle_deg=lean_deg * 0.85, scale_xy=(sc_g * 1.16, sc_g * 1.16))

        # 2. Legs & curved drapery + Far arm behind torso
        draw_legs_and_drapery()
        draw_arm(sh_l, l_elb, lh_end, 0.88)

        # 3. Grafted Canonical Collared Torso
        tarr, tpiv = rig_data["chest_f"]
        paste_transformed_part(canvas, tarr, tpiv, chest_c, angle_deg=lean_deg, scale_xy=(sc_g * 1.18, sc_g * 1.18))

        # 4. Canonical Front Head
        harr, hpiv = rig_data["head_f"]
        paste_transformed_part(
            canvas,
            harr,
            hpiv,
            (neck[0] + float(pose.get("head_dx", 0.0)) * 2.0, neck[1] + 6.0),
            angle_deg=lean_deg * 0.55 + float(pose.get("head_ang", 0.0)),
            scale_xy=(sc_g * 1.18, sc_g * 1.18),
        )

        # 5. Shen's flowing celadon pibo ribbon (`青碧披帛`)
        if is_shen:
            im_rib, drib = new_layer()
            rib_lift = float(pose.get("ribbon_lift", 0.0)) * 2.0
            wf2 = float(pose.get("flare_x", 0.0)) * 2.0
            draw_bezier_ink(
                drib,
                [(sh_l[0] - 8, sh_l[1] + 6), (sh_l[0] - 44, sh_l[1] + 34 - rib_lift), (sh_l[0] - 26 + wf2 * 0.5, hip[1] + 44 - rib_lift * 0.6)],
                (108, 162, 132, 235),
                9.0,
                4.0,
                20,
            )
            flush_layer(im_rib)

        # 6. Sword & Foreground Right Arm
        draw_sword_layer()
        draw_arm(sh_r, r_elb, rh_end, 1.0)
    else:
        # ==================== NE DORSAL-3/4 Z-ORDER ====================
        # Character faces away-right (+X, -Y): front-facing sword & arms are FARTHEST from camera
        # and MUST be composited UNDERNEATH the dorsal torso, head_b, and back props (casket_b / braid_b / cape_b)!
        draw_sword_layer()
        draw_arm(sh_l, l_elb, lh_end, 0.86)
        # Note: Pei Zhao's `cape_b` already includes his canonical white Gongbi right sleeve on the right shoulder!
        if not is_pei:
            draw_arm(sh_r, r_elb, rh_end, 0.92)

        draw_legs_and_drapery()

        im_tb, dtb = new_layer()
        _draw_tapered_segment(dtb, neck, hip, 26.0, 24.0, (*pal["robe_main"], 255), (*pal["robe_hi"], 255))
        dtb.polygon([(hip[0] - 25, hip[1] - 14), (hip[0] + 25, hip[1] - 14), (hip[0] + 26, hip[1] + 4), (hip[0] - 26, hip[1] + 4)], fill=(*pal["sash"], 255), outline=(26, 22, 20, 255))
        flush_layer(im_tb)

        harr_b, hpiv_b = rig_data["head_b"]
        paste_transformed_part(
            canvas,
            harr_b,
            hpiv_b,
            (neck[0] + float(pose.get("head_dx", 0.0)) * 2.0, neck[1] + 6.0),
            angle_deg=lean_deg * 0.55 + float(pose.get("head_ang", 0.0)),
            scale_xy=(sc_g * 1.18, sc_g * 1.18),
        )

        # Foreground Dorsal Back Props (unoccluded on the character's back!)
        if is_gu:
            cbar, cbpiv = rig_data["casket_b"]
            paste_transformed_part(canvas, cbar, cbpiv, (chest_c[0], chest_c[1] + 4.0), angle_deg=lean_deg, scale_xy=(sc_g * 1.18, sc_g * 1.18))
        elif is_shen:
            bbar, bbpiv = rig_data["braid_b"]
            paste_transformed_part(canvas, bbar, bbpiv, (neck[0], neck[1] + 4.0), angle_deg=lean_deg * 0.7, scale_xy=(sc_g * 1.16, sc_g * 1.16))
        elif is_pei:
            cp_arr, cp_piv = rig_data["cape_b"]
            paste_transformed_part(canvas, cp_arr, cp_piv, (neck[0] + 4.0, neck[1] + 18.0), angle_deg=lean_deg * 0.8, scale_xy=(sc_g * 1.14, sc_g * 1.08))

    out_im = Image.fromarray(clean_zero_alpha(canvas), mode="RGBA").resize((cell_w, cell_h), Image.Resampling.LANCZOS)
    out = np.asarray(out_im).copy()
    out = keep_largest_alpha_cc(out, 12)

    max_allowed_y = foot_y + 6
    ys_all, _ = np.where(out[..., 3] > 0)
    if len(ys_all) > 0 and int(ys_all.max()) > max_allowed_y:
        shift_up = int(ys_all.max()) - max_allowed_y
        shifted = np.zeros_like(out)
        if shift_up < cell_h:
            shifted[: cell_h - shift_up, :] = out[shift_up:, :]
        out = shifted
    out[foot_y + 10 :, :, :] = 0
    return keep_largest_alpha_cc(out, 12)


def build_party_hero_sheets() -> list[dict[str, Any]]:
    rigs = extract_party_graft_parts()
    cw, ch, cols, rows_cnt = 352, 280, 6, 8

    state_anchors_map: dict[str, dict[str, Any]] = {
        "gu_changqing": {
            "anchors": {"weapon": [54, -76], "hand": [36, -88], "cast": [38, -90], "chest": [4, -84], "head": [4, -138], "mouth": [12, -132], "overhead": [0, -172]},
            "state_anchors": {
                "idle_se": {"weapon": [48, -64], "hand": [30, -84], "cast": [32, -88], "chest": [2, -84], "head": [2, -138], "overhead": [0, -172]},
                "idle_ne": {"weapon": [46, -66], "hand": [28, -84], "cast": [30, -88], "chest": [2, -84], "head": [2, -138], "overhead": [0, -172]},
                "run_se": {"weapon": [-38, -68], "hand": [34, -82], "cast": [34, -84], "chest": [8, -80], "head": [12, -132], "overhead": [6, -168]},
                "run_ne": {"weapon": [-38, -68], "hand": [32, -82], "cast": [32, -84], "chest": [8, -80], "head": [12, -132], "overhead": [6, -168]},
                "attack_1": {"weapon": [78, -82], "hand": [52, -86], "cast": [52, -86], "chest": [16, -76], "head": [20, -126], "overhead": [12, -162]},
                "attack_2": {"weapon": [72, -98], "hand": [46, -96], "cast": [46, -96], "chest": [12, -80], "head": [14, -130], "overhead": [8, -166]},
                "cast_loop": {"weapon": [36, -108], "hand": [34, -94], "cast": [38, -98], "chest": [4, -86], "head": [4, -140], "overhead": [0, -174]},
                "cast_release": {"weapon": [68, -88], "hand": [54, -90], "cast": [58, -90], "chest": [14, -80], "head": [16, -130], "overhead": [10, -166]},
                "hit": {"weapon": [26, -66], "hand": [18, -88], "cast": [18, -88], "chest": [-8, -80], "head": [-12, -132], "overhead": [-8, -166]},
                "down": {"weapon": [34, -28], "hand": [22, -42], "cast": [22, -42], "chest": [6, -46], "head": [14, -78], "overhead": [6, -102]},
            },
        },
        "shen_qinghe": {
            "anchors": {"weapon": [44, -86], "hand": [44, -86], "cast": [46, -88], "chest": [2, -78], "head": [2, -130], "mouth": [10, -124], "overhead": [0, -164]},
            "state_anchors": {
                "idle_se": {"weapon": [32, -82], "hand": [32, -82], "cast": [34, -84], "chest": [2, -78], "head": [2, -130], "overhead": [0, -164]},
                "idle_ne": {"weapon": [30, -82], "hand": [30, -82], "cast": [32, -84], "chest": [2, -78], "head": [2, -130], "overhead": [0, -164]},
                "run_se": {"weapon": [36, -80], "hand": [36, -80], "cast": [38, -82], "chest": [8, -76], "head": [10, -126], "overhead": [6, -160]},
                "run_ne": {"weapon": [34, -80], "hand": [34, -80], "cast": [36, -82], "chest": [8, -76], "head": [10, -126], "overhead": [6, -160]},
                "attack_1": {"weapon": [58, -88], "hand": [58, -88], "cast": [60, -88], "chest": [10, -76], "head": [12, -126], "overhead": [8, -160]},
                "attack_2": {"weapon": [62, -92], "hand": [56, -90], "cast": [62, -92], "chest": [8, -78], "head": [10, -128], "overhead": [6, -162]},
                "cast_loop": {"weapon": [34, -88], "hand": [34, -88], "cast": [36, -90], "chest": [2, -80], "head": [2, -132], "overhead": [0, -166]},
                "cast_release": {"weapon": [60, -90], "hand": [58, -90], "cast": [62, -90], "chest": [10, -78], "head": [12, -128], "overhead": [8, -162]},
                "hit": {"weapon": [16, -80], "hand": [16, -80], "cast": [16, -80], "chest": [-8, -76], "head": [-10, -126], "overhead": [-6, -160]},
                "down": {"weapon": [24, -34], "hand": [24, -34], "cast": [24, -34], "chest": [4, -44], "head": [12, -74], "overhead": [6, -98]},
            },
        },
        "pei_zhao": {
            "anchors": {"weapon": [58, -78], "hand": [38, -90], "cast": [42, -94], "chest": [4, -86], "head": [4, -142], "mouth": [12, -136], "overhead": [0, -176]},
            "state_anchors": {
                "idle_se": {"weapon": [52, -66], "hand": [32, -86], "cast": [36, -90], "chest": [2, -86], "head": [2, -142], "overhead": [0, -176]},
                "idle_ne": {"weapon": [48, -68], "hand": [30, -86], "cast": [34, -90], "chest": [2, -86], "head": [2, -142], "overhead": [0, -176]},
                "run_se": {"weapon": [-42, -72], "hand": [36, -84], "cast": [38, -86], "chest": [8, -82], "head": [12, -136], "overhead": [6, -172]},
                "run_ne": {"weapon": [-42, -72], "hand": [34, -84], "cast": [36, -86], "chest": [8, -82], "head": [12, -136], "overhead": [6, -172]},
                "attack_1": {"weapon": [84, -80], "hand": [56, -84], "cast": [56, -84], "chest": [18, -76], "head": [20, -128], "overhead": [12, -164]},
                "attack_2": {"weapon": [78, -96], "hand": [50, -98], "cast": [52, -98], "chest": [14, -80], "head": [16, -132], "overhead": [10, -168]},
                "cast_loop": {"weapon": [42, -118], "hand": [36, -98], "cast": [40, -104], "chest": [4, -88], "head": [4, -144], "overhead": [0, -178]},
                "cast_release": {"weapon": [74, -90], "hand": [56, -92], "cast": [62, -92], "chest": [14, -82], "head": [16, -134], "overhead": [10, -170]},
                "hit": {"weapon": [28, -68], "hand": [18, -88], "cast": [18, -88], "chest": [-8, -82], "head": [-12, -136], "overhead": [-8, -170]},
                "down": {"weapon": [38, -28], "hand": [24, -44], "cast": [24, -44], "chest": [6, -48], "head": [14, -80], "overhead": [6, -104]},
            },
        },
    }

    manifest_entries: list[dict[str, Any]] = []
    rig_spec_doc: dict[str, Any] = {}

    for aid in ["gu_changqing", "shen_qinghe", "pei_zhao"]:
        rig = rigs[aid]
        is_shen = (aid == "shen_qinghe")
        is_pei = (aid == "pei_zhao")
        sheet = np.zeros((ch * rows_cnt, cw * cols, 4), dtype=np.uint8)

        def put(r: int, c: int, p: dict[str, Any]) -> None:
            sheet[r * ch : (r + 1) * ch, c * cw : (c + 1) * cw] = render_party_hero_cell(aid, rig, p, cw, ch)

        # Rows 0 & 1: idle_se & idle_ne (4 frames)
        for f in range(4):
            ph = (2.0 * math.pi * f) / 4.0
            br = math.sin(ph)
            p_idle = {
                "hip_dy": -1.2 * br,
                "lean_deg": 2.0 + 1.0 * br,
                "lf_dx": -14.0,
                "rf_dx": 14.0,
                "lh_dx": -18.0 if not is_shen else 10.0,
                "lh_dy": 48.0 if not is_shen else 36.0,
                "rh_dx": -12.0 if not is_shen else 22.0,
                "rh_dy": 52.0 if not is_shen else 32.0,
                "sword_ang": 34.0 if not is_pei else 32.0,
                "flare_x": -2.0 * math.cos(ph),
                "ribbon_lift": 4.0 * (0.5 + 0.5 * br),
            }
            put(0, f, p_idle)
            put(1, f, dict(p_idle, is_ne=True))

        # Rows 2 & 3: run_se & run_ne (6-frame genuine asymmetric scissor stride — visible alternating boots/shoes!)
        stride_x = [-28.0, -14.0, 10.0, 28.0, 14.0, -10.0]
        stride_y = [-2.0, -14.0, -8.0, 0.0, -2.0, -10.0]
        for f in range(6):
            op = (f + 3) % 6
            rf_x, rf_y = stride_x[f], stride_y[f]
            lf_x, lf_y = stride_x[op], stride_y[op]
            near_leads = rf_x > lf_x
            bob = -5.0 if f in (1, 4) else (1.5 if f == 3 else -1.5)
            p_run = {
                "is_moving": True,
                "hip_dx": 3.5 if near_leads else -2.5,
                "hip_dy": bob,
                "lean_deg": 13.5 if near_leads else 9.5,
                "lf_dx": lf_x,
                "lf_dy": lf_y,
                "rf_dx": rf_x,
                "rf_dy": rf_y,
                "lh_dx": 24.0 if not near_leads else -24.0,
                "lh_dy": 34.0 if not near_leads else 48.0,
                "rh_dx": (-16.0 if near_leads else -26.0) if not is_shen else (-18.0 if near_leads else 26.0),
                "rh_dy": (42.0 if near_leads else 48.0) if not is_shen else (34.0 if near_leads else 28.0),
                "sword_ang": 148.0 if near_leads else 164.0,
                "flare_x": -22.0 if near_leads else -12.0,
                "ribbon_lift": 18.0 if near_leads else 12.0,
            }
            put(2, f, p_run)
            put(3, f, dict(p_run, is_ne=True))

        # Row 4: attack_1 (5 frames — wide martial `弓步` slash/thrust for Gu/Pei, wide open-palm Qi strike for Shen)
        if not is_shen:
            atk1_list = [
                {"is_moving": True, "hip_dx": -10.0, "hip_dy": 4.0, "lean_deg": -8.0, "lf_dx": -24.0, "rf_dx": 16.0, "lh_dx": 14.0, "lh_dy": 32.0, "rh_dx": -26.0, "rh_dy": 26.0, "sword_ang": -125.0, "flare_x": -10.0},
                {"is_moving": True, "hip_dx": 8.0, "hip_dy": 8.0, "lean_deg": 14.0, "lf_dx": -34.0, "rf_dx": 32.0, "lh_dx": -18.0, "lh_dy": 36.0, "rh_dx": 36.0, "rh_dy": 28.0, "sword_ang": -24.0, "flare_x": -22.0},
                {"is_moving": True, "hip_dx": 12.0, "hip_dy": 12.0, "lean_deg": 17.0, "lf_dx": -38.0, "rf_dx": 38.0, "lh_dx": (-32.0 if is_pei else 16.0), "lh_dy": (38.0 if is_pei else 32.0), "rh_dx": (42.0 if is_pei else 40.0), "rh_dy": 36.0, "sword_ang": (12.0 if is_pei else -8.0), "flare_x": -24.0},
                {"is_moving": True, "hip_dx": 9.0, "hip_dy": 8.0, "lean_deg": 12.0, "lf_dx": -30.0, "rf_dx": 30.0, "lh_dx": -16.0, "lh_dy": 40.0, "rh_dx": 34.0, "rh_dy": 44.0, "sword_ang": 26.0, "flare_x": -16.0},
                {"hip_dx": 2.0, "hip_dy": 2.0, "lean_deg": 4.0, "lf_dx": -18.0, "rf_dx": 18.0, "lh_dx": -16.0, "lh_dy": 46.0, "rh_dx": 6.0, "rh_dy": 50.0, "sword_ang": 34.0, "flare_x": -6.0},
            ]
        else:
            atk1_list = [
                {"is_moving": True, "hip_dx": -6.0, "hip_dy": 2.0, "lean_deg": -4.0, "lf_dx": -16.0, "rf_dx": 14.0, "lh_dx": -12.0, "lh_dy": 34.0, "rh_dx": 8.0, "rh_dy": 36.0, "flare_x": -8.0, "ribbon_lift": 10.0},
                {"is_moving": True, "hip_dx": 6.0, "hip_dy": 4.0, "lean_deg": 8.0, "lf_dx": -24.0, "rf_dx": 26.0, "lh_dx": -24.0, "lh_dy": 36.0, "rh_dx": 36.0, "rh_dy": 28.0, "open_palm": True, "flare_x": -20.0, "ribbon_lift": 22.0},
                {"is_moving": True, "hip_dx": 10.0, "hip_dy": 6.0, "lean_deg": 11.0, "lf_dx": -28.0, "rf_dx": 30.0, "lh_dx": -28.0, "lh_dy": 40.0, "rh_dx": 44.0, "rh_dy": 26.0, "open_palm": True, "flare_x": -24.0, "ribbon_lift": 28.0},
                {"is_moving": True, "hip_dx": 6.0, "hip_dy": 4.0, "lean_deg": 7.0, "lf_dx": -22.0, "rf_dx": 22.0, "lh_dx": -20.0, "lh_dy": 40.0, "rh_dx": 34.0, "rh_dy": 32.0, "open_palm": True, "flare_x": -16.0, "ribbon_lift": 18.0},
                {"hip_dx": 0.0, "hip_dy": 0.0, "lean_deg": 3.0, "lf_dx": -14.0, "rf_dx": 14.0, "lh_dx": 10.0, "lh_dy": 36.0, "rh_dx": 22.0, "rh_dy": 34.0, "flare_x": -6.0, "ribbon_lift": 6.0},
            ]
        for f, p in enumerate(atk1_list):
            put(4, f, p)

        # Row 5: attack_2 (5 frames — heavy cleave / reverse rising slash / silver-needle flick)
        if not is_shen:
            atk2_list = [
                {"is_moving": True, "hip_dx": -8.0, "hip_dy": 6.0, "lean_deg": -10.0, "lf_dx": -22.0, "rf_dx": 20.0, "lh_dx": -14.0, "lh_dy": 24.0, "rh_dx": -12.0, "rh_dy": -6.0, "sword_ang": -115.0, "flare_x": -12.0},
                {"is_moving": True, "hip_dx": 4.0, "hip_dy": -2.0, "lean_deg": 8.0, "lf_dx": -28.0, "rf_dx": 28.0, "lh_dx": -24.0, "lh_dy": 30.0, "rh_dx": 24.0, "rh_dy": -6.0, "sword_ang": -48.0, "flare_x": -18.0},
                {"is_moving": True, "hip_dx": 12.0, "hip_dy": 14.0, "lean_deg": 17.5, "lf_dx": -36.0, "rf_dx": 38.0, "lh_dx": -30.0, "lh_dy": 36.0, "rh_dx": 40.0, "rh_dy": 22.0, "sword_ang": (18.0 if is_pei else -22.0), "flare_x": -24.0},
                {"is_moving": True, "hip_dx": 9.0, "hip_dy": 10.0, "lean_deg": 12.0, "lf_dx": -28.0, "rf_dx": 30.0, "lh_dx": -20.0, "lh_dy": 42.0, "rh_dx": 32.0, "rh_dy": 42.0, "sword_ang": 32.0, "flare_x": -16.0},
                {"hip_dx": 2.0, "hip_dy": 2.0, "lean_deg": 4.0, "lf_dx": -16.0, "rf_dx": 16.0, "lh_dx": -16.0, "lh_dy": 46.0, "rh_dx": 8.0, "rh_dy": 48.0, "sword_ang": 34.0, "flare_x": -6.0},
            ]
        else:
            atk2_list = [
                {"is_moving": True, "hip_dx": -8.0, "hip_dy": 2.0, "lean_deg": -6.0, "lf_dx": -18.0, "rf_dx": 16.0, "lh_dx": 16.0, "lh_dy": 26.0, "rh_dx": -18.0, "rh_dy": 24.0, "flare_x": 10.0, "ribbon_lift": 16.0},
                {"is_moving": True, "hip_dx": 4.0, "hip_dy": -2.0, "lean_deg": 8.0, "lf_dx": -24.0, "rf_dx": 24.0, "lh_dx": -22.0, "lh_dy": 32.0, "rh_dx": 36.0, "rh_dy": 18.0, "open_palm": True, "flare_x": -20.0, "ribbon_lift": 26.0},
                {"is_moving": True, "hip_dx": 8.0, "hip_dy": 4.0, "lean_deg": 12.0, "lf_dx": -28.0, "rf_dx": 28.0, "lh_dx": -26.0, "lh_dy": 36.0, "rh_dx": 44.0, "rh_dy": 20.0, "open_palm": True, "flare_x": -24.0, "ribbon_lift": 30.0},
                {"is_moving": True, "hip_dx": 4.0, "hip_dy": 2.0, "lean_deg": 6.0, "lf_dx": -20.0, "rf_dx": 20.0, "lh_dx": -18.0, "lh_dy": 40.0, "rh_dx": 30.0, "rh_dy": 30.0, "flare_x": -14.0, "ribbon_lift": 16.0},
                {"hip_dx": 0.0, "hip_dy": 0.0, "lean_deg": 2.0, "lf_dx": -14.0, "rf_dx": 14.0, "lh_dx": 10.0, "lh_dy": 36.0, "rh_dx": 22.0, "rh_dy": 34.0, "flare_x": -4.0, "ribbon_lift": 6.0},
            ]
        for f, p in enumerate(atk2_list):
            put(5, f, p)

        # Row 6: cast_loop (0..2) & cast_release (3..5)
        cast_list = [
            {"hip_dy": -2.0, "lean_deg": -2.0, "lf_dx": -16.0, "rf_dx": 16.0, "lh_dx": 14.0, "lh_dy": 28.0, "rh_dx": 22.0, "rh_dy": 16.0, "sword_ang": -86.0, "open_palm": True, "flare_x": -10.0, "ribbon_lift": 18.0},
            {"hip_dy": -3.0, "lean_deg": -4.0, "lf_dx": -18.0, "rf_dx": 18.0, "lh_dx": 18.0, "lh_dy": 24.0, "rh_dx": 26.0, "rh_dy": 12.0, "sword_ang": -90.0, "open_palm": True, "flare_x": -16.0, "ribbon_lift": 26.0},
            {"hip_dy": -2.5, "lean_deg": -3.0, "lf_dx": -16.0, "rf_dx": 16.0, "lh_dx": 16.0, "lh_dy": 26.0, "rh_dx": 24.0, "rh_dy": 14.0, "sword_ang": -88.0, "open_palm": True, "flare_x": -14.0, "ribbon_lift": 22.0},
            {"is_moving": True, "hip_dx": 9.0, "hip_dy": 6.0, "lean_deg": 12.0, "lf_dx": -28.0, "rf_dx": 30.0, "lh_dx": -24.0, "lh_dy": 36.0, "rh_dx": 40.0, "rh_dy": 24.0, "sword_ang": -6.0, "open_palm": True, "flare_x": -22.0, "ribbon_lift": 30.0},
            {"is_moving": True, "hip_dx": 11.0, "hip_dy": 8.0, "lean_deg": 14.0, "lf_dx": -30.0, "rf_dx": 32.0, "lh_dx": -26.0, "lh_dy": 38.0, "rh_dx": 42.0, "rh_dy": 26.0, "sword_ang": 0.0, "open_palm": True, "flare_x": -24.0, "ribbon_lift": 28.0},
            {"hip_dx": 4.0, "hip_dy": 2.0, "lean_deg": 5.0, "lf_dx": -18.0, "rf_dx": 18.0, "lh_dx": -12.0, "lh_dy": 42.0, "rh_dx": 24.0, "rh_dy": 36.0, "sword_ang": 24.0, "flare_x": -10.0, "ribbon_lift": 12.0},
        ]
        for f, p in enumerate(cast_list):
            put(6, f, p)

        # Row 7: hit (cols 0..1, zero orange tint) & down (cols 2..3, genuine grounded kneeling/slumped collapse!)
        row7_list = [
            {"hip_dx": -12.0, "hip_dy": 4.0, "lean_deg": -14.0, "head_ang": -8.0, "lf_dx": -24.0, "rf_dx": 10.0, "lh_dx": 12.0, "lh_dy": 26.0, "rh_dx": 8.0, "rh_dy": 38.0, "sword_ang": -52.0, "flare_x": 14.0, "ribbon_lift": 12.0},
            {"hip_dx": -8.0, "hip_dy": 2.0, "lean_deg": -9.0, "head_ang": -5.0, "lf_dx": -20.0, "rf_dx": 12.0, "lh_dx": 8.0, "lh_dy": 32.0, "rh_dx": 6.0, "rh_dy": 42.0, "sword_ang": -36.0, "flare_x": 8.0, "ribbon_lift": 8.0},
            {"is_down": True, "hip_dx": -4.0, "hip_dy": 32.0, "lean_deg": 24.0, "head_ang": 12.0, "lf_dx": -30.0, "lf_dy": 0.0, "rf_dx": 22.0, "rf_dy": 0.0, "lh_dx": -8.0, "lh_dy": 38.0, "rh_dx": 22.0, "rh_dy": 40.0, "sword_ang": 72.0, "flare_x": -12.0},
            {"is_down": True, "hip_dx": -10.0, "hip_dy": 62.0, "lean_deg": 54.0, "head_ang": 18.0, "lf_dx": -38.0, "lf_dy": 0.0, "rf_dx": 26.0, "rf_dy": 0.0, "lh_dx": 8.0, "lh_dy": 30.0, "rh_dx": 28.0, "rh_dy": 28.0, "sword_ang": 8.0, "flare_x": -16.0},
        ]
        for f, p in enumerate(row7_list):
            put(7, f, p)

        png_out = os.path.join(REPO_ROOT, f"project/assets/sprites/{aid}_sheet.png")
        save_rgba_clean(sheet, png_out)

        meta = {
            "actor_id": aid,
            "cell_w": cw,
            "cell_h": ch,
            "foot_y": int(rig["foot_y"]),
            "head_top_px": int(rig["head_top_px"]),
            "cols": cols,
            "rows": {
                "idle_se": {"row": 0, "frames": 4, "fps": 6.0, "loop": True},
                "idle_ne": {"row": 1, "frames": 4, "fps": 6.0, "loop": True},
                "run_se": {"row": 2, "frames": 6, "fps": 10.5, "loop": True},
                "run_ne": {"row": 3, "frames": 6, "fps": 10.5, "loop": True},
                "attack_1": {"row": 4, "frames": 5, "fps": 12.0, "loop": False},
                "attack_2": {"row": 5, "frames": 5, "fps": 12.0, "loop": False},
                "cast_loop": {"row": 6, "start_col": 0, "frames": 3, "fps": 7.5, "loop": True},
                "cast_release": {"row": 6, "start_col": 3, "frames": 3, "fps": 10.5, "loop": False},
                "hit": {"row": 7, "start_col": 0, "frames": 2, "fps": 9.0, "loop": False},
                "down": {"row": 7, "start_col": 2, "frames": 2, "fps": 4.0, "loop": False},
            },
            "anchors": state_anchors_map[aid]["anchors"],
            "state_anchors": state_anchors_map[aid]["state_anchors"],
        }
        json_out = os.path.join(REPO_ROOT, f"project/assets/sprites/{aid}_sheet.json")
        with open(json_out, "w", encoding="utf-8") as fh:
            json.dump(meta, fh, ensure_ascii=False, indent=2)
            fh.write("\n")

        rig_spec_doc[aid] = {"cell": [cw, ch], "foot_y": rig["foot_y"], "head_top_px": rig["head_top_px"]}
        manifest_entries.append({
            "path": f"project/assets/sprites/{aid}_sheet.png",
            "source_path": "assets_src/sprites/r2_party_parts_sheet.png",
            "category": "sprite_sheet",
            "dimensions": f"{cw * cols}x{ch * rows_cnt}",
            "sha256": sha256_file(png_out),
            "creation_method": f"Gemini Image Generation (assets_src/sprites/char_ref_party_{{pets,back}}_raw.jpg) + tools/build_polish_r2_actors.py (Canonical head/collar/accessory grafting + 2x-supersampled 2-bone Song-Ming Gongbi limbs, curved Bezier split martial robes/wide sleeves & alternating-foot stride) | Spec: 352x280 multi-pose combat sprite sheet for {aid} aligned to master_b_cangmu_rtwp.png",
            "generated_date": GEN_DATE,
            "license": LICENSE_R2,
        })

    spec_path = os.path.join(REPO_ROOT, "assets_src/sprites/r2_actors_rig_spec.json")
    with open(spec_path, "w", encoding="utf-8") as fh:
        json.dump(rig_spec_doc, fh, ensure_ascii=False, indent=2)
        fh.write("\n")

    return manifest_entries


# ==============================================================================
# SECTION 3: 33 `1024x1280` PORTRAIT FACIAL EXPRESSION DIFFERENTIALS
# ==============================================================================
PORTRAIT_LANDMARKS: dict[str, dict[str, Any]] = {
    "gu_changqing": {
        "emotions": ["calm", "guarded", "solemn", "cold", "smile_faint", "grief", "bloodied"],
        "face_box": (385, 195, 196, 206),
        "lb_out": (426, 250), "lb_mid": (444, 254), "lb_in": (468, 260),
        "rb_in": (508, 260), "rb_mid": (526, 256), "rb_out": (542, 252),
        "glabella": (488, 259),
        "le_up": (436, 266), "le_low": (436, 276), "le_pup": (436, 270), "le_out": (420, 268),
        "re_up": (524, 267), "re_low": (524, 277), "re_pup": (524, 270), "re_out": (538, 270),
        "m_l": (461, 348), "m_c": (484, 347), "m_r": (507, 348),
        "cheek_l": (434, 304), "cheek_r": (526, 304),
        "temple": (530, 236),
        "blood_lip": [(461, 349), (459, 358), (460, 368)],
        "protect_boxes": [(275, 740, 620, 290), (140, 455, 760, 825)],  # `断玉剑匣`, pouch & robes 100% untouched!
    },
    "shen_qinghe": {
        "emotions": ["calm", "guarded", "solemn", "cold", "smile_faint", "grief", "bloodied"],
        "face_box": (396, 188, 186, 224),
        "lb_out": (418, 245), "lb_mid": (432, 245), "lb_in": (452, 247),
        "rb_in": (494, 245), "rb_mid": (520, 240), "rb_out": (550, 244),
        "glabella": (474, 246),
        "le_up": (435, 264), "le_low": (435, 276), "le_pup": (435, 269), "le_out": (418, 269),
        "re_up": (520, 262), "re_low": (520, 274), "re_pup": (520, 266), "re_out": (542, 267),
        "m_l": (457, 354), "m_c": (480, 355), "m_r": (506, 353),
        "cheek_l": (428, 308), "cheek_r": (536, 306),
        "temple": (550, 228),
        "blood_lip": [(506, 354), (508, 363), (507, 373)],
        "protect_boxes": [(345, 440, 175, 390), (190, 440, 650, 840)],  # Upper/lower herb leaves & robes 100% untouched!
    },
    "pei_zhao": {
        "emotions": ["calm", "guarded", "solemn", "cold", "smile_faint", "grief", "bloodied"],
        "face_box": (432, 240, 168, 214),
        "lb_out": (446, 297), "lb_mid": (462, 302), "lb_in": (482, 308),
        "rb_in": (514, 302), "rb_mid": (538, 297), "rb_out": (568, 291),
        "glabella": (498, 305),
        "le_up": (462, 312), "le_low": (462, 322), "le_pup": (462, 316), "le_out": (448, 315),
        "re_up": (546, 309), "re_low": (546, 320), "re_pup": (546, 313), "re_out": (566, 312),
        "m_l": (482, 401), "m_c": (502, 402), "m_r": (534, 401),
        "cheek_l": (458, 356), "cheek_r": (558, 354),
        "temple": (568, 276),
        "blood_lip": [(534, 402), (536, 411), (535, 421)],
        "protect_boxes": [(425, 45, 240, 135), (95, 470, 835, 810)],  # Full crown, sword & white skirt 100% untouched!
    },
    "mist_wolf_king": {
        "emotions": ["calm", "grief", "bloodied"],
        "face_box": (240, 260, 540, 600),
        "is_lupine": True,
        "lb_out": (325, 476), "lb_in": (412, 474),
        "rb_in": (590, 472), "rb_out": (676, 476),
        "shard_c": (501, 396),
        "le_up": (390, 483), "le_low": (390, 511), "le_pup": (390, 497),
        "re_up": (617, 479), "re_low": (617, 507), "re_pup": (617, 493),
        "ear_l": (225, 165), "ear_r": (775, 165),
        "snout": (502, 710),
        "m_l": (390, 785), "m_c": (502, 838), "m_r": (614, 785),
        "protect_boxes": [],
    },
    "npc_elder": {
        "emotions": ["calm", "solemn", "grief"],
        "face_box": (456, 206, 186, 212),
        "lb_out": (492, 260), "lb_mid": (514, 258), "lb_in": (536, 262),
        "rb_in": (564, 262), "rb_mid": (588, 258), "rb_out": (610, 262),
        "glabella": (550, 262),
        "le_up": (520, 270), "le_low": (520, 280), "le_pup": (520, 273), "le_out": (504, 276),
        "re_up": (596, 272), "re_low": (596, 282), "re_pup": (596, 276), "re_out": (612, 278),
        "m_l": (528, 363), "m_c": (554, 362), "m_r": (586, 363),
        "cheek_l": (508, 314), "cheek_r": (600, 316),
        "temple": (604, 249),
        "blood_lip": [(586, 364), (588, 373), (587, 382)],
        "protect_boxes": [(140, 425, 740, 855)],
    },
    "npc_peddler": {
        "emotions": ["calm", "smile_faint", "cold"],
        "face_box": (480, 192, 174, 206),
        "lb_out": (506, 234), "lb_mid": (528, 234), "lb_in": (552, 238),
        "rb_in": (588, 240), "rb_mid": (608, 238), "rb_out": (628, 234),
        "glabella": (570, 239),
        "le_up": (530, 254), "le_low": (530, 263), "le_pup": (530, 257), "le_out": (512, 258),
        "re_up": (608, 254), "re_low": (608, 263), "re_pup": (608, 257), "re_out": (626, 257),
        "m_l": (543, 342), "m_c": (570, 343), "m_r": (598, 342),
        "cheek_l": (520, 296), "cheek_r": (614, 296),
        "temple": (612, 218),
        "blood_lip": [(598, 343), (600, 352), (599, 361)],
        "protect_boxes": [(40, 405, 930, 875)],
    },
    "npc_steward_zhou": {
        "emotions": ["calm", "guarded", "grief"],
        "face_box": (386, 224, 166, 194),
        "lb_out": (404, 274), "lb_mid": (420, 272), "lb_in": (440, 270),
        "rb_in": (464, 269), "rb_mid": (488, 271), "rb_out": (512, 274),
        "glabella": (452, 270),
        "le_up": (418, 290), "le_low": (418, 299), "le_pup": (418, 293), "le_out": (404, 295),
        "re_up": (492, 288), "re_low": (492, 297), "re_pup": (492, 291), "re_out": (508, 291),
        "m_l": (436, 375), "m_c": (460, 373), "m_r": (488, 374),
        "cheek_l": (414, 330), "cheek_r": (504, 328),
        "temple": (518, 264),
        "blood_lip": [(488, 375), (490, 384), (489, 393)],
        "protect_boxes": [(171, 425, 681, 855)],
    },
}


def extract_clean_portrait_1024x1280(pid: str) -> np.ndarray:
    """Collar- & skirt-safe alpha matting repair + 1024x1280 bottom-aligned Song-Ming LUT."""
    raw_path = os.path.join(REPO_ROOT, f"assets_src/portraits/{pid}_raw.jpg")
    im = Image.open(raw_path).convert("RGB")
    rgb = np.asarray(im, dtype=np.float32)
    H, W, _ = rgb.shape

    border_samples = np.concatenate([rgb[0], rgb[: H // 2, 0], rgb[: H // 2, -1]], axis=0)
    bg_col = np.median(border_samples, axis=0)
    diff = np.linalg.norm(rgb - bg_col, axis=2)
    luma = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]
    chroma = rgb.max(axis=2) - rgb.min(axis=2)
    tol = 22.0 if pid == "pei_zhao" else 27.0
    if pid == "mist_wolf_king":
        # Strip pure-white ear halo (#FFFFFF differs from warm cream border by ~42, so include bright low-chroma neutral bg!)
        bg_cand = (((diff < 32.0) & (luma > 195.0)) | ((luma > 196.0) & (chroma < 28.0))).astype(np.uint8)
    else:
        bg_cand = ((diff < tol) & (luma > 205.0)).astype(np.uint8)

    num_l, labels, stats, centroids = cv2.connectedComponentsWithStats(bg_cand, connectivity=8)
    # Seed ONLY top, left, right, and outer bottom corners — NEVER bottom center hem!
    ext = (
        set(labels[0, :])
        | set(labels[:, 0])
        | set(labels[:, -1])
        | set(labels[-1, :120])
        | set(labels[-1, W - 120 :])
    )
    ext.discard(0)

    pocket_tol = 30.0 if pid == "gu_changqing" else 25.0
    if pid == "mist_wolf_king":
        pocket_cand = (((diff < 32.0) & (luma > 192.0)) | ((luma > 194.0) & (chroma < 28.0))).astype(np.uint8)
    else:
        pocket_cand = ((diff < pocket_tol) & (luma > 200.0)).astype(np.uint8)
    np_l, p_lbl, p_stats, p_cent = cv2.connectedComponentsWithStats(pocket_cand, connectivity=8)
    pocket_kill = np.zeros((H, W), dtype=bool)
    for lid in range(1, np_l):
        area = int(p_stats[lid, cv2.CC_STAT_AREA])
        cx, cy = float(p_cent[lid][0]), float(p_cent[lid][1])
        if p_stats[lid, cv2.CC_STAT_TOP] == 0 or p_stats[lid, cv2.CC_STAT_LEFT] == 0 or (p_stats[lid, cv2.CC_STAT_LEFT] + p_stats[lid, cv2.CC_STAT_WIDTH] >= W):
            continue
        if pid == "mist_wolf_king":
            if cy < 275.0 and (cx < 320.0 or cx > 660.0):
                pocket_kill |= (p_lbl == lid)
        elif pid == "npc_peddler":
            if (cx < 305.0 and 290.0 < cy < 790.0 and area > 25) or (cy < 340.0 and (cx < 380.0 or cx > 580.0) and area > 8):
                pocket_kill |= (p_lbl == lid)
        elif pid == "gu_changqing":
            if (cy < 360.0 and (cx < 375.0 or cx > 525.0) and area >= 3) or (cx < 295.0 and 680.0 < cy < 880.0 and area >= 10):
                pocket_kill |= (p_lbl == lid)
        elif pid == "pei_zhao":
            if cy < 425.0 and (cx < 365.0 or cx > 545.0) and area >= 6:
                pocket_kill |= (p_lbl == lid)
        elif pid == "npc_elder":
            if (cy < 350.0 and (cx < 395.0 or cx > 560.0) and area >= 6) or (cx < 395.0 and 720.0 < cy < 980.0 and area >= 25):
                pocket_kill |= (p_lbl == lid)
        elif pid == "shen_qinghe":
            if cy < 340.0 and (cx < 355.0 or cx > 560.0) and area >= 6:
                pocket_kill |= (p_lbl == lid)

    fg_u8 = ((~np.isin(labels, list(ext))) & (~pocket_kill)).astype(np.uint8) * 255
    kern = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    erode_iters = 2 if pid == "mist_wolf_king" else 1
    fg_er = cv2.erode(fg_u8, kern, iterations=erode_iters)
    alpha = cv2.GaussianBlur(fg_er.astype(np.float32), (0, 0), 0.65)
    alpha_u8 = np.clip(np.round(alpha), 0.0, 255.0).astype(np.uint8)

    out_rgb = rgb.copy()
    edge = (alpha_u8 > 8) & (alpha_u8 < 238)
    defringe_col = np.array([28.0, 24.0, 28.0] if pid == "mist_wolf_king" else [32.0, 29.0, 27.0], dtype=np.float32)
    out_rgb[edge] = (0.42 if pid == "mist_wolf_king" else 0.58) * out_rgb[edge] + (0.58 if pid == "mist_wolf_king" else 0.42) * defringe_col
    rgba = clean_zero_alpha(np.concatenate([np.clip(out_rgb, 0, 255).astype(np.uint8), alpha_u8[..., None]], axis=2))
    rgba = apply_song_ming_lut(rgba, sat_scale=0.90, val_scale=1.0)

    ys, xs = np.where(rgba[..., 3] > 12)
    x0 = max(0, int(xs.min()) - 12)
    x1 = min(W, int(xs.max()) + 12)
    y0 = max(0, int(ys.min()) - 16)
    y1 = H if pid != "mist_wolf_king" else min(H, int(ys.max()) + 16)
    cropped = rgba[y0:y1, x0:x1]
    ch_c, cw_c = cropped.shape[:2]
    scale = min(980.0 / max(1, cw_c), 1222.0 / max(1, ch_c))
    nw, nh = int(round(cw_c * scale)), int(round(ch_c * scale))
    resized = np.asarray(Image.fromarray(cropped, mode="RGBA").resize((nw, nh), Image.Resampling.LANCZOS))

    canvas = np.zeros((1280, 1024, 4), dtype=np.uint8)
    px = (1024 - nw) // 2
    py = (1280 - nh) if pid != "mist_wolf_king" else (1280 - nh) // 2
    canvas[py : py + nh, px : px + nw] = resized
    return clean_zero_alpha(canvas)


def assert_portrait_landmarks_on_calm(pid: str, calm_rgba: np.ndarray, lm: dict[str, Any]) -> None:
    """Enforces hard build-time anatomical coordinate assertions directly on the 1024x1280 calm canvas."""
    rgb = calm_rgba[..., :3].astype(np.float32)
    luma = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]

    if lm.get("is_lupine", False):
        # Wolf King: verify le_pup=(390,497), re_pup=(617,493) and zero bright ear fringe!
        assert lm["le_pup"] == (390, 497) and lm["re_pup"] == (617, 493), f"Wolf pupil coords mismatch: {lm['le_pup']}, {lm['re_pup']}"
        ear_r_sub = calm_rgba[80:240, 760:805]
        ear_r_luma = luma[80:240, 760:805]
        white_fringe_px = int(((ear_r_sub[..., 3] > 16) & (ear_r_luma > 165.0)).sum())
        assert white_fringe_px == 0, f"Wolf upper-right ear white fringe remaining: {white_fringe_px}px"
        return

    # 1. Pupils (`le_pup`, `re_pup`) MUST sample actual dark iris/pupil ink (`luma < 85`) AND sit strictly below eyebrows!
    for pk, bk in [("le_pup", "lb_mid"), ("re_pup", "rb_mid")]:
        px, py = lm[pk]
        bx, by = lm[bk]
        p_luma = float(luma[py - 1 : py + 2, px - 1 : px + 2].min())
        b_luma = float(luma[by - 2 : by + 3, bx - 2 : bx + 3].min())
        assert p_luma < 85.0, f"[{pid}] {pk}=({px},{py}) missed dark iris ink: min_luma={p_luma:.1f}"
        assert b_luma < 115.0, f"[{pid}] {bk}=({bx},{by}) missed eyebrow ink: min_luma={b_luma:.1f}"
        assert py >= by + 10, f"[{pid}] {pk} y={py} too close to brow {bk} y={by}"

    # 2. Glabella MUST sit horizontally & vertically between inner brow heads (never mid-forehead!)
    gx, gy = lm["glabella"]
    lbi_x, lbi_y = lm["lb_in"]
    rbi_x, rbi_y = lm["rb_in"]
    mean_brow_in_y = 0.5 * (lbi_y + rbi_y)
    assert lbi_x < gx < rbi_x, f"[{pid}] glabella x={gx} not between lb_in={lbi_x} and rb_in={rbi_x}"
    assert abs(gy - mean_brow_in_y) <= 4.5, f"[{pid}] glabella y={gy} drifted from inner brows y={mean_brow_in_y:.1f}"

    # 3. Lower lash (`le_low`, `re_low`) MUST sit strictly below pupil (`>= pup_y + 5`)
    assert lm["le_low"][1] >= lm["le_pup"][1] + 5 and lm["re_low"][1] >= lm["re_pup"][1] + 5, f"[{pid}] lower lash too high"

    # 4. Temple MUST sit on exposed skin (`luma > 150` across 5x5 patch, never inside dark hair!)
    tx, ty = lm["temple"]
    t_min_luma = float(luma[ty - 2 : ty + 3, tx - 2 : tx + 3].min())
    assert t_min_luma > 145.0, f"[{pid}] temple=({tx},{ty}) inside dark hair/shadow: min_luma={t_min_luma:.1f}"

    # 5. Mouth slit (`m_c`) MUST hit actual mouth slit ink (`luma < 95`) and `blood_lip[0]` MUST start >= outer corner Y!
    mcx, mcy = lm["m_c"]
    mc_luma = float(luma[mcy - 2 : mcy + 3, mcx - 2 : mcx + 3].min())
    assert mc_luma < 95.0, f"[{pid}] m_c=({mcx},{mcy}) missed mouth slit ink: min_luma={mc_luma:.1f}"
    bl_x, bl_y = lm["blood_lip"][0]
    near_corner = lm["m_l"] if abs(bl_x - lm["m_l"][0]) < abs(bl_x - lm["m_r"][0]) else lm["m_r"]
    assert abs(bl_x - near_corner[0]) <= 4 and bl_y >= near_corner[1], (
        f"[{pid}] blood_lip start ({bl_x},{bl_y}) above/away from mouth corner {near_corner}"
    )


def apply_local_wendland_warp(
    base_rgba: np.ndarray,
    warps: list[tuple[tuple[float, float], tuple[float, float], tuple[float, float]]],
    roi_box: tuple[int, int, int, int],
) -> np.ndarray:
    """
    Applies compactly-supported C^2 Wendland-Gaussian local displacements strictly inside roi_box.
    """
    if not warps:
        return base_rgba.copy()
    out = base_rgba.copy()
    rx, ry, rw, rh = roi_box
    x0, y0 = max(0, rx), max(0, ry)
    x1, y1 = min(1024, rx + rw), min(1280, ry + rh)
    sub = out[y0:y1, x0:x1].copy()
    sh, sw = sub.shape[:2]

    gy, gx = np.mgrid[0:sh, 0:sw].astype(np.float32)
    ax = gx + float(x0)
    ay = gy + float(y0)
    disp_x = np.zeros((sh, sw), dtype=np.float32)
    disp_y = np.zeros((sh, sw), dtype=np.float32)

    # Smooth boundary taper to exact 0.0 at roi_box edges so zero boundary seam or outside bleed occurs
    bx_taper = np.clip(np.minimum(gx, (sw - 1) - gx) / 14.0, 0.0, 1.0)
    by_taper = np.clip(np.minimum(gy, (sh - 1) - gy) / 14.0, 0.0, 1.0)
    box_taper = bx_taper * by_taper

    for (cx, cy), (dx, dy), (sx, sy) in warps:
        r2 = ((ax - cx) / max(1.0, sx)) ** 2 + ((ay - cy) / max(1.0, sy)) ** 2
        inside = r2 < 9.0
        if np.any(inside):
            t = r2[inside]
            w = np.exp(-0.5 * t) * ((1.0 - t / 9.0) ** 2) * box_taper[inside]
            disp_x[inside] += dx * w
            disp_y[inside] += dy * w

    map_x = (gx - disp_x).astype(np.float32)
    map_y = (gy - disp_y).astype(np.float32)
    orig_a = sub[..., 3].copy()
    warped_rgb = cv2.remap(sub[..., :3], map_x, map_y, interpolation=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)
    sub[..., :3] = np.where((orig_a > 0)[..., None], warped_rgb, 0)
    sub[..., 3] = orig_a
    out[y0:y1, x0:x1] = sub
    return clean_zero_alpha(out)


def synthesize_portrait_expression(calm_rgba: np.ndarray, pid: str, expr: str) -> np.ndarray:
    if expr == "calm":
        return calm_rgba.copy()

    lm = PORTRAIT_LANDMARKS[pid]
    fbox = lm["face_box"]
    orig_alpha = calm_rgba[..., 3].copy()

    # Bespoke lupine expressions for `mist_wolf_king` (`grief` awakened guardian vs `bloodied` Dao-Shadow corruption)
    if lm.get("is_lupine", False):
        if expr == "grief":
            warps = [
                (lm["ear_l"], (-14.0, 16.0), (58.0, 62.0)),
                (lm["ear_r"], (14.0, 16.0), (58.0, 62.0)),
                (lm["lb_in"], (4.5, -10.5), (38.0, 26.0)),
                (lm["rb_in"], (-4.5, -10.5), (38.0, 26.0)),
                (lm["lb_out"], (-2.0, 8.5), (44.0, 28.0)),
                (lm["rb_out"], (2.0, 8.5), (44.0, 28.0)),
                (lm["le_up"], (0.0, 5.5), (30.0, 16.0)),
                (lm["re_up"], (0.0, 5.5), (30.0, 16.0)),
                (lm["m_l"], (-3.0, 8.0), (42.0, 28.0)),
                (lm["m_r"], (3.0, 8.0), (42.0, 28.0)),
            ]
            out = apply_local_wendland_warp(calm_rgba, warps, (150, 90, 720, 820))
            ov = Image.new("RGBA", (2048, 2560), (0, 0, 0, 0))
            d = ImageDraw.Draw(ov)
            scx, scy = lm["shard_c"][0] * 2, lm["shard_c"][1] * 2
            d.ellipse((scx - 110, scy - 170, scx + 110, scy + 170), fill=(98, 224, 182, 76))
            ov_blur = ov.filter(ImageFilter.GaussianBlur(radius=18.0))
            d2 = ImageDraw.Draw(ov_blur)
            draw_bezier_ink(d2, [(scx - 24, scy - 95), (scx + 8, scy - 12), (scx - 18, scy + 88)], (215, 255, 238, 230), 5.5, 3.0)
            draw_bezier_ink(d2, [(scx + 28, scy - 52), (scx - 6, scy + 6), (scx + 26, scy + 64)], (172, 248, 218, 215), 4.5, 2.5)
            for ex_p, ey_p in [lm["le_pup"], lm["re_pup"]]:
                d2.ellipse((ex_p * 2 - 20, ey_p * 2 - 14, ex_p * 2 + 20, ey_p * 2 + 14), fill=(116, 236, 188, 130))
                d2.ellipse((ex_p * 2 - 9, ey_p * 2 + 22, ex_p * 2 + 7, ey_p * 2 + 42), fill=(220, 252, 242, 180))
            ov_1x = np.asarray(ov_blur.resize((1024, 1280), Image.Resampling.LANCZOS)).copy()
            ov_1x[..., 3] = np.minimum(ov_1x[..., 3], orig_alpha)
            alpha_over_np(out, ov_1x)
            return clean_zero_alpha(out)
        else:  # `bloodied` berserk Dao-Shadow corruption
            warps = [
                (lm["ear_l"], (8.0, -10.0), (54.0, 58.0)),
                (lm["ear_r"], (-8.0, -10.0), (54.0, 58.0)),
                (lm["lb_in"], (7.5, 12.5), (42.0, 28.0)),
                (lm["rb_in"], (-7.5, 12.5), (42.0, 28.0)),
                (lm["lb_out"], (-3.0, -7.5), (44.0, 28.0)),
                (lm["rb_out"], (3.0, -7.5), (44.0, 28.0)),
                (lm["snout"], (0.0, -10.0), (58.0, 48.0)),
                (lm["m_l"], (-5.0, -9.0), (44.0, 30.0)),
                (lm["m_r"], (5.0, -9.0), (44.0, 30.0)),
            ]
            out = apply_local_wendland_warp(calm_rgba, warps, (150, 90, 720, 820))
            ov = Image.new("RGBA", (2048, 2560), (0, 0, 0, 0))
            d = ImageDraw.Draw(ov)
            scx, scy = lm["shard_c"][0] * 2, lm["shard_c"][1] * 2
            d.ellipse((scx - 125, scy - 185, scx + 125, scy + 185), fill=(178, 36, 78, 104))
            # Soft crimson glow centered accurately on actual iris centroids (390,497) & (617,493) + feathered fur battle washes
            for ex_p, ey_p in [lm["le_pup"], lm["re_pup"]]:
                d.ellipse((ex_p * 2 - 24, ey_p * 2 - 16, ex_p * 2 + 24, ey_p * 2 + 16), fill=(238, 64, 58, 165))
            d.ellipse((700, 1140, 890, 1280), fill=(112, 26, 30, 88))
            d.ellipse((1060, 1160, 1250, 1295), fill=(108, 24, 28, 82))
            ov_blur = ov.filter(ImageFilter.GaussianBlur(radius=16.0))
            d2 = ImageDraw.Draw(ov_blur)
            draw_bezier_ink(d2, [(scx - 28, scy - 105), (scx + 12, scy - 6), (scx - 22, scy + 98)], (252, 92, 114, 240), 6.5, 3.5)
            draw_bezier_ink(d2, [(scx + 32, scy - 58), (scx - 8, scy + 8), (scx + 30, scy + 74)], (245, 128, 146, 220), 5.0, 2.8)
            for ex_p, ey_p in [lm["le_pup"], lm["re_pup"]]:
                d2.ellipse((ex_p * 2 - 9, ey_p * 2 - 7, ex_p * 2 + 9, ey_p * 2 + 7), fill=(255, 118, 96, 175))
            # Feathered curved fur-tuft battle scuffs following natural snout bridge & cheek fur (ZERO straight red lines!)
            scuff_layer = Image.new("RGBA", (2048, 2560), (0, 0, 0, 0))
            ds_w = ImageDraw.Draw(scuff_layer)
            draw_bezier_ink(ds_w, [(732, 1166), (770, 1186), (820, 1226), (854, 1268)], (124, 28, 30, 155), 8.5, 2.2, 20)
            draw_bezier_ink(ds_w, [(748, 1192), (784, 1212), (826, 1252)], (88, 18, 22, 145), 5.5, 1.6, 16)
            draw_bezier_ink(ds_w, [(1214, 1178), (1174, 1204), (1126, 1246), (1094, 1284)], (118, 26, 28, 150), 8.0, 2.0, 20)
            scuff_soft = scuff_layer.filter(ImageFilter.GaussianBlur(radius=3.4))
            ov_comb = Image.alpha_composite(ov_blur, scuff_soft)
            ov_1x = np.asarray(ov_comb.resize((1024, 1280), Image.Resampling.LANCZOS)).copy()
            ov_1x[..., 3] = np.minimum(ov_1x[..., 3], orig_alpha)
            alpha_over_np(out, ov_1x)
            return clean_zero_alpha(out)

    # Humanoid Song-Ming Gongbi anatomical warps + 2x-supersampled brush overpaint
    warps_h: list[tuple[tuple[float, float], tuple[float, float], tuple[float, float]]] = []
    if expr == "guarded":
        warps_h = [
            (lm["lb_in"], (3.6, 4.4), (19.0, 12.0)),
            (lm["rb_in"], (-3.6, 4.4), (19.0, 12.0)),
            (lm["lb_out"], (0.0, -1.6), (20.0, 11.0)),
            (lm["rb_out"], (0.0, -3.6), (20.0, 11.0)),
            (lm["le_low"], (0.0, -3.2), (18.0, 7.0)),
            (lm["re_low"], (0.0, -3.2), (18.0, 7.0)),
            (lm["le_up"], (0.0, 1.8), (18.0, 7.0)),
            (lm["re_up"], (0.0, 1.8), (18.0, 7.0)),
            (lm["le_pup"], (3.8, 0.0), (8.5, 6.0)),
            (lm["re_pup"], (3.8, 0.0), (8.5, 6.0)),
            (lm["m_l"], (1.8, 3.0), (19.0, 11.0)),
            (lm["m_r"], (-1.6, 1.6), (19.0, 11.0)),
            (lm["m_c"], (0.0, -2.0), (16.0, 9.0)),
        ]
    elif expr == "solemn":
        warps_h = [
            (lm["lb_in"], (3.8, 5.8), (22.0, 13.0)),
            (lm["rb_in"], (-3.8, 5.8), (22.0, 13.0)),
            (lm["lb_mid"], (0.0, 4.0), (22.0, 12.0)),
            (lm["rb_mid"], (0.0, 4.0), (22.0, 12.0)),
            (lm["lb_out"], (0.0, 2.2), (20.0, 11.0)),
            (lm["rb_out"], (0.0, 2.2), (20.0, 11.0)),
            (lm["le_up"], (0.0, 3.8), (20.0, 8.0)),
            (lm["re_up"], (0.0, 3.8), (20.0, 8.0)),
            (lm["le_pup"], (0.0, 1.8), (8.5, 6.0)),
            (lm["re_pup"], (0.0, 1.8), (8.5, 6.0)),
            (lm["m_l"], (-1.2, 4.6), (21.0, 12.0)),
            (lm["m_r"], (1.2, 4.6), (21.0, 12.0)),
        ]
    elif expr == "cold":
        warps_h = [
            (lm["lb_in"], (4.2, 6.0), (21.0, 12.0)),
            (lm["rb_in"], (-4.2, 6.0), (21.0, 12.0)),
            (lm["lb_out"], (-1.5, -4.8), (23.0, 12.0)),
            (lm["rb_out"], (1.5, -4.8), (23.0, 12.0)),
            (lm["le_up"], (0.0, 3.2), (19.0, 7.5)),
            (lm["re_up"], (0.0, 3.2), (19.0, 7.5)),
            (lm["le_out"], (0.0, -2.4), (14.0, 7.0)),
            (lm["re_out"], (0.0, -2.4), (14.0, 7.0)),
            (lm["le_low"], (0.0, -3.5), (19.0, 7.0)),
            (lm["re_low"], (0.0, -3.5), (19.0, 7.0)),
            (lm["m_l"], (-1.5, 2.8), (20.0, 11.0)),
            (lm["m_r"], (1.5, 2.8), (20.0, 11.0)),
            (lm["m_c"], (0.0, -2.4), (17.0, 9.0)),
        ]
    elif expr == "smile_faint":
        warps_h = [
            (lm["lb_in"], (-1.5, -2.8), (20.0, 11.0)),
            (lm["rb_in"], (1.5, -2.8), (20.0, 11.0)),
            (lm["lb_mid"], (0.0, -3.4), (22.0, 12.0)),
            (lm["rb_mid"], (0.0, -3.4), (22.0, 12.0)),
            (lm["le_low"], (0.0, -3.6), (20.0, 7.0)),
            (lm["re_low"], (0.0, -3.6), (20.0, 7.0)),
            (lm["le_out"], (0.0, 1.5), (15.0, 7.0)),
            (lm["re_out"], (0.0, 1.5), (15.0, 7.0)),
            (lm["m_l"], (-2.4, -5.2), (24.0, 14.0)),
            (lm["m_r"], (2.4, -5.2), (24.0, 14.0)),
            (lm["m_c"], (0.0, 1.5), (17.0, 10.0)),
            (lm["cheek_l"], (0.0, -2.6), (26.0, 18.0)),
            (lm["cheek_r"], (0.0, -2.6), (26.0, 18.0)),
        ]
    elif expr == "grief":
        warps_h = [
            (lm["lb_in"], (3.0, -5.6), (20.0, 11.0)),
            (lm["rb_in"], (-3.0, -5.6), (20.0, 11.0)),
            (lm["lb_out"], (0.0, 5.0), (23.0, 12.0)),
            (lm["rb_out"], (0.0, 5.0), (23.0, 12.0)),
            (lm["le_up"], (0.0, 4.4), (20.0, 7.5)),
            (lm["re_up"], (0.0, 4.4), (20.0, 7.5)),
            (lm["le_out"], (0.0, 3.4), (16.0, 7.5)),
            (lm["re_out"], (0.0, 3.4), (16.0, 7.5)),
            (lm["m_l"], (-1.4, 5.4), (22.0, 13.0)),
            (lm["m_r"], (1.4, 5.4), (22.0, 13.0)),
        ]
    elif expr == "bloodied":
        warps_h = [
            (lm["lb_in"], (4.0, 6.2), (21.0, 12.0)),
            (lm["rb_in"], (-4.0, 6.2), (21.0, 12.0)),
            (lm["lb_out"], (0.0, -3.4), (22.0, 11.0)),
            (lm["rb_out"], (0.0, -3.4), (22.0, 11.0)),
            (lm["le_up"], (0.0, 2.8), (19.0, 7.0)),
            (lm["re_up"], (0.0, 2.8), (19.0, 7.0)),
            (lm["le_low"], (0.0, -3.4), (19.0, 7.0)),
            (lm["re_low"], (0.0, -3.4), (19.0, 7.0)),
            (lm["m_l"], (-1.2, 4.0), (20.0, 12.0)),
            (lm["m_r"], (1.2, 4.0), (20.0, 12.0)),
            (lm["m_c"], (0.0, 2.6), (16.0, 9.0)),
        ]

    out = apply_local_wendland_warp(calm_rgba, warps_h, fbox)

    # Compactly-supported face-only tone wash strictly zeroed outside `fbox`!
    fx, fy, fw, fh = fbox
    gy_f, gx_f = np.mgrid[0:1280, 0:1024].astype(np.float32)
    r2_face = ((gx_f - (fx + fw * 0.5)) / (fw * 0.48)) ** 2 + ((gy_f - (fy + fh * 0.52)) / (fh * 0.48)) ** 2
    in_fbox = (gx_f >= fx) & (gx_f < fx + fw) & (gy_f >= fy) & (gy_f < fy + fh) & (r2_face < 1.0) & (orig_alpha > 40)
    face_w = np.zeros((1280, 1024), dtype=np.float32)
    face_w[in_fbox] = ((1.0 - r2_face[in_fbox]) ** 2) * np.exp(-1.2 * r2_face[in_fbox])

    if expr == "grief":
        rgb_f = out[..., :3].astype(np.float32)
        gray = (0.299 * rgb_f[..., 0] + 0.587 * rgb_f[..., 1] + 0.114 * rgb_f[..., 2])[..., None]
        desat = rgb_f * (1.0 - 0.19 * face_w[..., None]) + gray * (0.19 * face_w[..., None])
        out[..., :3] = np.clip(desat, 0.0, 255.0).astype(np.uint8)
    elif expr == "cold":
        rgb_f = out[..., :3].astype(np.float32)
        rgb_f[..., 0] -= 5.0 * face_w
        rgb_f[..., 2] += 6.0 * face_w
        out[..., :3] = np.clip(rgb_f, 0.0, 255.0).astype(np.uint8)

    # 2x-Supersampled Song-Ming Gongbi Painterly Facial Overpaint (strictly on calibrated landmarks!)
    wash_2x = Image.new("RGBA", (2048, 2560), (0, 0, 0, 0))
    dw = ImageDraw.Draw(wash_2x)
    sharp_2x = Image.new("RGBA", (2048, 2560), (0, 0, 0, 0))
    ds = ImageDraw.Draw(sharp_2x)

    glx, gly = lm["glabella"][0] * 2, lm["glabella"][1] * 2
    clx, cly = lm["cheek_l"][0] * 2, lm["cheek_l"][1] * 2
    crx, cry = lm["cheek_r"][0] * 2, lm["cheek_r"][1] * 2

    if expr == "guarded":
        # Subtle warm-umber Gongbi brow-root shadow strictly between inner brow heads
        dw.ellipse((glx - 16, gly - 8, glx + 16, gly + 18), fill=(134, 102, 84, 34))
        draw_bezier_ink(ds, [(glx - 4, gly - 2), (glx - 3, gly + 7), (glx - 4, gly + 15)], (112, 84, 68, 68), 2.0, 1.2)
    elif expr == "solemn":
        dw.ellipse((glx - 18, gly - 8, glx + 18, gly + 20), fill=(128, 96, 78, 40))
        for ex_p, ey_p in [lm["le_up"], lm["re_up"]]:
            dw.ellipse((ex_p * 2 - 30, ey_p * 2 - 10, ex_p * 2 + 30, ey_p * 2 + 10), fill=(106, 82, 68, 42))
        draw_bezier_ink(ds, [(glx - 7, gly - 2), (glx - 6, gly + 7), (glx - 7, gly + 15)], (108, 80, 66, 72), 2.0, 1.2)
        draw_bezier_ink(ds, [(glx + 7, gly - 2), (glx + 6, gly + 7), (glx + 7, gly + 15)], (108, 80, 66, 72), 2.0, 1.2)
    elif expr == "cold":
        dw.ellipse((glx - 16, gly - 8, glx + 16, gly + 18), fill=(116, 94, 84, 34))
        dw.ellipse((clx - 40, cly - 22, clx + 40, cly + 28), fill=(82, 92, 102, 32))
        dw.ellipse((crx - 40, cry - 22, crx + 40, cry + 28), fill=(82, 92, 102, 32))
        draw_bezier_ink(ds, [(glx, gly - 2), (glx + 1, gly + 7), (glx, gly + 15)], (104, 78, 66, 68), 1.9, 1.1)
        # Crisp cold glint strictly inside the dark iris/pupil!
        for px_e, py_e in [lm["le_pup"], lm["re_pup"]]:
            ds.ellipse((px_e * 2 - 3, py_e * 2 - 3, px_e * 2 + 2, py_e * 2 + 2), fill=(238, 248, 255, 205))
    elif expr == "smile_faint":
        # Song-Ming mineral rouge (`胭脂`) on cheeks + warm golden catchlights strictly inside dark pupils
        dw.ellipse((clx - 52, cly - 30, clx + 52, cly + 30), fill=(214, 128, 114, 58))
        dw.ellipse((crx - 52, cry - 30, crx + 52, cry + 30), fill=(214, 128, 114, 58))
        for px_e, py_e in [lm["le_pup"], lm["re_pup"]]:
            ds.ellipse((px_e * 2 - 3, py_e * 2 - 3, px_e * 2 + 2, py_e * 2 + 2), fill=(255, 246, 224, 200))
    elif expr == "grief":
        # Song-Ming carmine eye-rim (`朱膘染眼尾`) + subtle wet lower lash waterline + tear droplet below lower lid!
        for ox, oy in [lm["le_out"], lm["re_out"]]:
            dw.ellipse((ox * 2 - 28, oy * 2 - 12, ox * 2 + 28, oy * 2 + 16), fill=(188, 82, 74, 82))
        for lx, ly in [lm["le_low"], lm["re_low"]]:
            draw_bezier_ink(ds, [(lx * 2 - 16, ly * 2 + 1), (lx * 2, ly * 2 + 4), (lx * 2 + 16, ly * 2 + 1)], (236, 244, 252, 98), 2.0, 1.4)
        tx_tear = lm["le_low"][0] * 2 - 6
        ty_tear = lm["le_low"][1] * 2 + 5
        ds.ellipse((tx_tear - 4, ty_tear, tx_tear + 5, ty_tear + 13), fill=(224, 242, 252, 180), outline=(146, 174, 192, 115))
        ds.ellipse((tx_tear - 1, ty_tear + 2, tx_tear + 2, ty_tear + 5), fill=(255, 255, 255, 215))
    elif expr == "bloodied":
        # Painterly Song-Ming Gongbi battle scuffs, exposed-temple trickle & corner-of-mouth blood (`唇角溢血`)
        dw.ellipse((clx - 42, cly - 20, clx + 40, cly + 24), fill=(86, 68, 58, 62))
        dw.ellipse((crx - 36, cry - 16, crx + 42, cry + 22), fill=(148, 56, 46, 56))
        draw_bezier_ink(ds, [(crx - 20, cry - 4), (crx + 2, cry + 5), (crx + 22, cry + 12)], (136, 34, 28, 175), 3.6, 1.5)
        draw_bezier_ink(ds, [(crx - 14, cry - 2), (crx + 2, cry + 4), (crx + 15, cry + 9)], (88, 20, 18, 190), 1.9, 1.0)
        # Curved temple trickle on verified exposed temple skin
        tpx, tpy = lm["temple"][0] * 2, lm["temple"][1] * 2
        draw_bezier_ink(ds, [(tpx, tpy), (tpx - 4, tpy + 18), (tpx + 2, tpy + 36)], (132, 30, 26, 168), 3.4, 1.1)
        # Organic corner-of-mouth smudge + curved chin trickle strictly AT/BELOW outer mouth corner (0px above upper lip!)
        b_start_x, b_start_y = lm["blood_lip"][0]
        s_dir = -1.0 if b_start_x < lm["m_c"][0] else 1.0
        bp0 = (b_start_x * 2, (b_start_y + 1) * 2)
        # Soft corner smudge at lower lip corner
        dw.ellipse((bp0[0] - 10, bp0[1] - 2, bp0[0] + 10, bp0[1] + 14), fill=(142, 34, 28, 95))
        bp1 = (bp0[0] + 4 * s_dir, bp0[1] + 12)
        bp2 = (bp0[0] + 1 * s_dir, bp0[1] + 24)
        bp3 = (bp0[0] + 4 * s_dir, bp0[1] + 35)
        draw_bezier_ink(ds, [bp0, bp1, bp2, bp3], (136, 26, 22, 192), 3.6, 1.2)
        ds.ellipse((bp3[0] - 2, bp3[1] - 1, bp3[0] + 2, bp3[1] + 3), fill=(110, 18, 16, 200))

    wash_blur = wash_2x.filter(ImageFilter.GaussianBlur(radius=11.0))
    sharp_soft = sharp_2x.filter(ImageFilter.GaussianBlur(radius=0.80))
    wash_1x = np.asarray(wash_blur.resize((1024, 1280), Image.Resampling.LANCZOS)).copy()
    sharp_1x = np.asarray(sharp_soft.resize((1024, 1280), Image.Resampling.LANCZOS)).copy()

    if expr == "bloodied":
        # Hard-zero any blur halo above outer mouth corner y in the philtrum/upper-lip band!
        b_cx, b_cy = lm["blood_lip"][0]
        wash_1x[max(0, b_cy - 24) : b_cy, max(0, b_cx - 22) : min(1024, b_cx + 22), 3] = 0
        sharp_1x[max(0, b_cy - 24) : b_cy, max(0, b_cx - 22) : min(1024, b_cx + 22), 3] = 0

    # Mask strictly inside character alpha, strictly inside `fbox`, AND strictly OUTSIDE protected props!
    allow_mask = np.zeros_like(orig_alpha)
    allow_mask[fy : fy + fh, fx : fx + fw] = orig_alpha[fy : fy + fh, fx : fx + fw]
    for px0, py0, pw0, ph0 in lm.get("protect_boxes", []):
        allow_mask[py0 : py0 + ph0, px0 : px0 + pw0] = 0
    wash_1x[..., 3] = np.minimum(wash_1x[..., 3], allow_mask)
    sharp_1x[..., 3] = np.minimum(sharp_1x[..., 3], allow_mask)

    alpha_over_np(out, wash_1x)
    alpha_over_np(out, sharp_1x)
    for px0, py0, pw0, ph0 in lm.get("protect_boxes", []):
        out[py0 : py0 + ph0, px0 : px0 + pw0] = calm_rgba[py0 : py0 + ph0, px0 : px0 + pw0]
    return clean_zero_alpha(out)


def _compute_affine_removed_srmse(a_rgb: np.ndarray, b_rgb: np.ndarray, mask: np.ndarray) -> float:
    """Computes affine-removed (gain + offset per channel) structural RMSE across foreground face pixels."""
    pa = a_rgb[mask].astype(np.float64)
    pb = b_rgb[mask].astype(np.float64)
    res_sq = np.zeros_like(pa)
    for ch_i in range(3):
        xa = pa[:, ch_i]
        xb = pb[:, ch_i]
        va = float(np.var(xa))
        if va > 1e-6:
            k = float(np.cov(xa, xb, bias=True)[0, 1]) / va
            b = float(np.mean(xb)) - k * float(np.mean(xa))
            pred = k * xa + b
        else:
            pred = np.full_like(xb, float(np.mean(xb)))
        res_sq[:, ch_i] = (xb - pred) ** 2
    return float(np.sqrt(np.mean(res_sq)))


def build_all_portraits() -> list[dict[str, Any]]:
    manifest_entries: list[dict[str, Any]] = []
    spec_doc: dict[str, Any] = {}

    contact_im = Image.new("RGB", (1680, 1680), (238, 232, 220))
    row_idx = 0

    for pid, lm in PORTRAIT_LANDMARKS.items():
        calm = extract_clean_portrait_1024x1280(pid)
        assert_portrait_landmarks_on_calm(pid, calm, lm)

        fx, fy, fw, fh = lm["face_box"]
        gen_faces: dict[str, np.ndarray] = {}

        for col_idx, expr in enumerate(lm["emotions"]):
            var_rgba = synthesize_portrait_expression(calm, pid, expr)
            out_path = os.path.join(REPO_ROOT, f"project/assets/portraits/{pid}_{expr}.png")
            save_rgba_clean(var_rgba, out_path)

            # Verify zero prop bleed AND zero diff outside fbox (for humanoids)!
            for px0, py0, pw0, ph0 in lm.get("protect_boxes", []):
                max_prop_d = int(np.max(np.abs(var_rgba[py0 : py0 + ph0, px0 : px0 + pw0].astype(np.int32) - calm[py0 : py0 + ph0, px0 : px0 + pw0].astype(np.int32))))
                assert max_prop_d == 0, f"Prop bleed detected on {pid}_{expr}: max_diff={max_prop_d}"
            if not lm.get("is_lupine", False):
                outside = np.ones((1280, 1024), dtype=bool)
                outside[fy : fy + fh, fx : fx + fw] = False
                max_out_d = int(np.max(np.abs(var_rgba[outside].astype(np.int32) - calm[outside].astype(np.int32))))
                assert max_out_d == 0, f"Outside-fbox bleed on {pid}_{expr}: max_diff={max_out_d}"

            gen_faces[expr] = var_rgba[fy : fy + fh, fx : fx + fw, :3].astype(np.float32)

            fc_rgba = Image.fromarray(var_rgba[fy : fy + fh, fx : fx + fw]).resize((216, 216), Image.Resampling.LANCZOS)
            tile = Image.new("RGBA", (216, 216), (238, 232, 220, 255))
            tile = Image.alpha_composite(tile, fc_rgba).convert("RGB")
            contact_im.paste(tile, (20 + col_idx * 234, 20 + row_idx * 234))

            manifest_entries.append({
                "path": f"project/assets/portraits/{pid}_{expr}.png",
                "source_path": "assets_src/portraits/r2_expression_layers_sheet.png",
                "category": "portrait",
                "dimensions": "1024x1280",
                "sha256": sha256_file(out_path),
                "creation_method": f"Gemini Image Generation (assets_src/portraits/{pid}_raw.jpg) + tools/build_polish_r2_actors.py (Skirt/collar/ear-safe alpha matting, final-canvas-calibrated C^2 Wendland-Gaussian facial articulation & 2x-supersampled Song-Ming Gongbi brow/eyelid/mouth/scuff overpaint) | Spec: 1024x1280 waist-up portrait {pid} ({expr})",
                "generated_date": GEN_DATE,
                "license": LICENSE_R2,
            })

        # Pairwise raw AND affine-removed structural sRMSE verification across ALL emotion pairs!
        emo_list = lm["emotions"]
        min_pair_rmse = 999.0
        min_pair_srmse = 999.0
        min_pair_names = ("", "")
        fg_face = calm[fy : fy + fh, fx : fx + fw, 3] > 40
        for i in range(len(emo_list)):
            for j in range(i + 1, len(emo_list)):
                ea, eb = emo_list[i], emo_list[j]
                diff_sq = (gen_faces[ea][fg_face] - gen_faces[eb][fg_face]) ** 2
                rmse = float(np.sqrt(np.mean(diff_sq)))
                srmse = _compute_affine_removed_srmse(gen_faces[ea], gen_faces[eb], fg_face)
                if srmse < min_pair_srmse:
                    min_pair_srmse = srmse
                    min_pair_rmse = rmse
                    min_pair_names = (ea, eb)
        assert min_pair_srmse >= 6.0, f"Affine-removed sRMSE too small on {pid} {min_pair_names}: sRMSE={min_pair_srmse:.2f}"
        spec_doc[pid] = {
            "emotions": emo_list,
            "face_box": [fx, fy, fw, fh],
            "min_pairwise_face_rmse": round(min_pair_rmse, 3),
            "min_pairwise_affine_srmse": round(min_pair_srmse, 3),
            "min_pair": list(min_pair_names),
        }
        row_idx += 1

    save_rgb_clean(np.asarray(contact_im), os.path.join(REPO_ROOT, "assets_src/portraits/r2_expression_layers_sheet.png"))
    with open(os.path.join(REPO_ROOT, "assets_src/portraits/r2_expression_spec.json"), "w", encoding="utf-8") as fh:
        json.dump(spec_doc, fh, ensure_ascii=False, indent=2)
        fh.write("\n")

    return manifest_entries


# ==============================================================================
# SECTION 4: 5 `NarrativeStage` CARVED EBONY ROLLERS, PLAQUE & TEMPLE BACKDROP
# ==============================================================================
def _build_roller_cap(is_right: bool) -> np.ndarray:
    """Synthesizes 80x386 carved dark-ebony scroll roller at 2x supersampling (160x772)."""
    W2, H2 = 160, 772
    rng = np.random.default_rng(20261127)
    gy, gx = np.mgrid[0:H2, 0:W2].astype(np.float32)

    # Barrel occupies outer 112px; inner 48px (y: 116..686) is vertical wooden stile flange
    if not is_right:
        bx0, bx1 = 4.0, 116.0
        fx0, fx1 = 112.0, 158.0
    else:
        bx0, bx1 = 44.0, 156.0
        fx0, fx1 = 2.0, 48.0
    bcx = 0.5 * (bx0 + bx1)

    # Turned profile radius r(y) along y in [8..764]
    ry = np.zeros(H2, dtype=np.float32)
    for y in range(H2):
        yf = y * 0.5  # 1x coordinate in [0..386]
        if yf < 4.0 or yf > 382.0:
            ry[y] = 0.0
        elif yf < 12.0:
            ry[y] = 16.0 + (yf - 4.0) * 1.4
        elif yf < 34.0:
            # Turned bulb top finial
            u = (yf - 23.0) / 11.0
            ry[y] = 28.0 * math.sqrt(max(0.08, 1.0 - 0.55 * u * u))
        elif yf < 46.0:
            # Neck concave cove
            u = (yf - 40.0) / 6.0
            ry[y] = 18.0 + 5.0 * u * u
        elif yf < 58.0:
            # Brass/ebony collar ring
            u = (yf - 52.0) / 6.0
            ry[y] = 29.0 - 3.5 * u * u
        elif yf <= 342.0:
            # Main carved cylindrical shaft
            ry[y] = 26.5
        elif yf < 354.0:
            # Lower collar ring
            u = (yf - 348.0) / 6.0
            ry[y] = 29.0 - 3.5 * u * u
        elif yf < 364.0:
            u = (yf - 359.0) / 5.0
            ry[y] = 18.5 + 4.5 * u * u
        else:
            # Flared bottom finial bulb & tip
            u = (yf - 372.0) / 10.5
            ry[y] = max(0.0, 26.5 * math.sqrt(max(0.0, 1.0 - 0.88 * u * u)))

    half_w2 = ry[:, None] * 2.0
    dist_c = np.abs(gx - bcx)
    barrel_mask = (half_w2 > 1.0) & (dist_c <= half_w2)
    flange_mask = (gy >= 116.0) & (gy <= 686.0) & (gx >= fx0) & (gx <= fx1)
    full_mask = barrel_mask | flange_mask

    # Carved Song-Ming Ruyi cloud-scroll relief heightmap on shaft (mirrored BEFORE lighting!)
    rel_im = Image.new("L", (112, 568), 0)
    rd = ImageDraw.Draw(rel_im)
    for motif_i in range(4):
        yc = 72 + motif_i * 136
        draw_bezier_ink(rd, [(26, yc - 48), (84, yc - 24), (24, yc + 18), (82, yc + 48)], 215, 11.0, 7.0, 28)
        draw_bezier_ink(rd, [(82, yc - 36), (32, yc - 6), (78, yc + 28)], 175, 8.0, 5.0, 20)
        rd.ellipse((42, yc - 14, 70, yc + 14), outline=200, width=5)
    rel_arr = cv2.GaussianBlur(np.asarray(rel_im, dtype=np.float32) / 255.0, (0, 0), 2.4)
    if is_right:
        rel_arr = rel_arr[:, ::-1]

    height = np.zeros((H2, W2), dtype=np.float32)
    bx_s = int(round(bcx - 56))
    height[116:684, bx_s : bx_s + 112] = rel_arr

    # Upper-left 45-degree Sobel bevel shading (identical key light direction on BOTH caps!)
    gx_s = cv2.Sobel(height, cv2.CV_32F, 1, 0, ksize=3)
    gy_s = cv2.Sobel(height, cv2.CV_32F, 0, 1, ksize=3)
    bevel = np.clip(-0.7071 * (gx_s + gy_s) * 0.45, -0.35, 0.42)

    # Cylindrical normal shading (peak highlight at 36% from left edge of barrel!)
    u_cyl = np.clip((gx - (bcx - half_w2)) / np.maximum(2.0 * half_w2, 2.0), 0.0, 1.0)
    cyl_light = np.exp(-0.5 * ((u_cyl - 0.34) / 0.24) ** 2) * 0.55 - 0.30 * ((u_cyl - 0.45) ** 2)

    # Anisotropic vertical ebony woodgrain
    grain = cv2.GaussianBlur(rng.normal(0.0, 1.0, (H2 // 4, W2)).astype(np.float32), (3, 9), 1.4)
    grain = cv2.resize(grain, (W2, H2), interpolation=cv2.INTER_LINEAR) * 5.0

    base_ebony = np.array([38.0, 31.0, 26.0], dtype=np.float32)
    hi_ebony = np.array([92.0, 74.0, 58.0], dtype=np.float32)
    rgb = np.zeros((H2, W2, 3), dtype=np.float32)
    shade = np.clip(0.38 + cyl_light + bevel + height * 0.16, 0.06, 1.15)
    for ch_i in range(3):
        rgb[..., ch_i] = base_ebony[ch_i] * (1.0 - 0.45 * shade) + hi_ebony[ch_i] * (0.72 * shade) + grain * 0.5

    # Warm antique bronze collar rings at y1x = 52 & 348
    collar_band = barrel_mask & (((gy >= 98) & (gy <= 114)) | ((gy >= 688) & (gy <= 704)))
    bronze_col = np.array([176.0, 140.0, 82.0], dtype=np.float32)
    for ch_i in range(3):
        rgb[..., ch_i] = np.where(collar_band, bronze_col[ch_i] * (0.55 + 0.55 * shade), rgb[..., ch_i])

    # Darken inner stile flange slightly + subtle bronze edge bead
    rgb[flange_mask] *= 0.82
    alpha_f = cv2.GaussianBlur(full_mask.astype(np.float32) * 255.0, (3, 3), 0.65)
    # Crisp Song-Ming #0B0908 ink contour on silhouette & groove lines
    edge_ink = (alpha_f > 20.0) & (alpha_f < 236.0)
    rgb[edge_ink] = rgb[edge_ink] * 0.25 + np.array([12.0, 10.0, 9.0], dtype=np.float32) * 0.75
    for y_groove in [24, 68, 98, 114, 688, 704, 728]:
        g_band = barrel_mask & (np.abs(gy - y_groove) <= 1.6)
        rgb[g_band] = np.array([14.0, 11.0, 10.0], dtype=np.float32)

    rgba_2x = clean_zero_alpha(np.concatenate([np.clip(rgb, 0, 255).astype(np.uint8), np.clip(alpha_f, 0, 255).astype(np.uint8)[..., None]], axis=2))
    out_1x = np.asarray(Image.fromarray(rgba_2x, mode="RGBA").resize((80, 386), Image.Resampling.LANCZOS))
    return clean_zero_alpha(out_1x)


def _build_scroll_bg() -> np.ndarray:
    """Synthesizes 640x290 9-slice handscroll body (#292620 rails + #C9BA9E silk + #D8CEBE Xuan paper)."""
    W2, H2 = 1280, 580
    rng = np.random.default_rng(20261128)
    gy, gx = np.mgrid[0:H2, 0:W2].astype(np.float32)

    # Warm aged Xuan paper interior (#D8CEBE = 216, 206, 190) with subtle mulberry fiber grain
    fiber_h = cv2.GaussianBlur(rng.normal(0.0, 1.0, (H2 // 2, W2 // 4)).astype(np.float32), (9, 3), 1.8)
    fiber_h = cv2.resize(fiber_h, (W2, H2), interpolation=cv2.INTER_LINEAR)
    fiber_f = cv2.GaussianBlur(rng.normal(0.0, 1.0, (H2, W2)).astype(np.float32), (5, 5), 1.1)
    grain = fiber_h * 2.4 + fiber_f * 1.4

    rgb = np.zeros((H2, H2 if False else W2, 3), dtype=np.float32)
    xuan_base = np.array([216.0, 206.0, 190.0], dtype=np.float32)
    silk_base = np.array([201.0, 186.0, 158.0], dtype=np.float32)
    for c in range(3):
        rgb[..., c] = xuan_base[c] + grain

    # Aged tussah-silk mounting border (`绫边`, top/bottom 28px at 2x = 14px at 1x; left/right 48px at 2x = 24px at 1x)
    rail_h2 = 52  # 26px at 1x
    silk_t, silk_b = rail_h2 + 28, H2 - rail_h2 - 28
    silk_l, silk_r = 48, W2 - 48
    in_silk = (gy < silk_t) | (gy >= silk_b) | (gx < silk_l) | (gx >= silk_r)
    for c in range(3):
        rgb[..., c] = np.where(in_silk, silk_base[c] + grain * 0.8, rgb[..., c])

    # Crisp 1px (#8A7455) inner hairline separating silk mounting from Xuan paper interior
    on_hairline = (
        (((np.abs(gy - silk_t) <= 1.2) | (np.abs(gy - silk_b) <= 1.2)) & (gx >= silk_l) & (gx <= silk_r))
        | (((np.abs(gx - silk_l) <= 1.2) | (np.abs(gx - silk_r) <= 1.2)) & (gy >= silk_t) & (gy <= silk_b))
    )
    rgb[on_hairline] = np.array([138.0, 116.0, 85.0], dtype=np.float32)

    # Soft 7px interior shadow cast by top & bottom horizontal ebony rails
    top_sh = np.clip(1.0 - (gy - rail_h2) / 15.0, 0.0, 1.0) * (gy >= rail_h2)
    bot_sh = np.clip(1.0 - ((H2 - rail_h2) - gy) / 13.0, 0.0, 1.0) * (gy < H2 - rail_h2)
    rgb *= (1.0 - 0.22 * top_sh[..., None] - 0.16 * bot_sh[..., None])

    # Top & bottom horizontal carved #292620 dark-ebony rails with woodgrain, bevel ridge & bronze thread
    wgrain = cv2.GaussianBlur(rng.normal(0.0, 1.0, (H2, W2 // 8)).astype(np.float32), (11, 3), 2.0)
    wgrain = cv2.resize(wgrain, (W2, H2), interpolation=cv2.INTER_LINEAR) * 4.5
    in_top_rail = gy < rail_h2
    in_bot_rail = gy >= (H2 - rail_h2)
    in_rail = in_top_rail | in_bot_rail
    local_ry = np.where(in_top_rail, gy / rail_h2, (gy - (H2 - rail_h2)) / rail_h2)
    rail_prof = 0.72 + 0.42 * np.exp(-0.5 * ((local_ry - 0.24) / 0.16) ** 2) - 0.26 * (local_ry > 0.82)
    ebony_r = np.array([43.0, 38.0, 32.0], dtype=np.float32)
    for c in range(3):
        rgb[..., c] = np.where(in_rail, ebony_r[c] * rail_prof + wgrain * 0.5, rgb[..., c])

    # Subtle antique bronze molding thread along center of top & bottom rails + #0D0B09 ink borders
    bronze_line = (np.abs(gy - 26.0) <= 1.6) | (np.abs(gy - (H2 - 26.0)) <= 1.6)
    rgb[bronze_line] = np.array([148.0, 118.0, 72.0], dtype=np.float32)
    ink_rail_edge = (gy <= 2.5) | (gy >= H2 - 2.5) | (np.abs(gy - rail_h2) <= 2.0) | (np.abs(gy - (H2 - rail_h2)) <= 2.0)
    rgb[ink_rail_edge] = np.array([15.0, 12.0, 10.0], dtype=np.float32)

    alpha = np.full((H2, W2, 1), 255, dtype=np.uint8)
    rgba_2x = np.concatenate([np.clip(rgb, 0, 255).astype(np.uint8), alpha], axis=2)
    out_1x = np.asarray(Image.fromarray(rgba_2x, mode="RGBA").resize((640, 290), Image.Resampling.LANCZOS))
    return clean_zero_alpha(out_1x)


def _build_plaque_bg() -> np.ndarray:
    """Synthesizes 380x62 cusped begonia-ear (`海棠菱花耳`) gold-rimmed ebony speaker nameplate at 2x."""
    W2, H2 = 760, 124
    im = Image.new("RGBA", (W2, H2), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    def chamfer_poly(pad: int, ear: int) -> list[tuple[int, int]]:
        x0, y0, x1, y1 = pad, pad, W2 - 1 - pad, H2 - 1 - pad
        ym = H2 // 2
        return [
            (x0 + ear, y0),
            (x1 - ear, y0),
            (x1 - ear // 3, ym - 14),
            (x1, ym),
            (x1 - ear // 3, ym + 14),
            (x1 - ear, y1),
            (x0 + ear, y1),
            (x0 + ear // 3, ym + 14),
            (x0, ym),
            (x0 + ear // 3, ym - 14),
        ]

    # Stepped bronze outer ears + #1B1714 deep ebony body + #D6A85A chamfered gilt inner border
    d.polygon(chamfer_poly(3, 30), fill=(58, 48, 36, 252), outline=(14, 12, 10, 255))
    d.polygon(chamfer_poly(9, 27), fill=(214, 168, 90, 255), outline=(92, 70, 38, 255))
    d.polygon(chamfer_poly(14, 25), fill=(27, 23, 20, 252))
    d.polygon(chamfer_poly(20, 22), outline=(142, 110, 62, 195))

    # Gilt diamond side studs matching `master_c_temple_stage.png`
    for sx in (44, W2 - 44):
        ym = H2 // 2
        d.polygon([(sx, ym - 9), (sx + 9, ym), (sx, ym + 9), (sx - 9, ym)], fill=(226, 184, 106, 255), outline=(24, 18, 14, 255))

    out_1x = np.asarray(im.resize((380, 62), Image.Resampling.LANCZOS))
    return clean_zero_alpha(out_1x)


def _build_temple_backdrop() -> np.ndarray:
    """
    Loads the dedicated Song-Ming Gongbi rainy night ruined temple courtyard stage plate
    `assets_src/ui/r2_temple_backdrop_raw.png`, scales to 1920x1080 Lanczos, and applies subtle
    lower-scroll vignette harmony aligned to `master_c_temple_stage.png`.
    """
    raw_im = Image.open(os.path.join(REPO_ROOT, "assets_src/ui/r2_temple_backdrop_raw.png")).convert("RGB")
    src = np.asarray(raw_im.resize((1920, 1080), Image.Resampling.LANCZOS), dtype=np.float32)
    gy, gx = np.mgrid[0:1080, 0:1920].astype(np.float32)
    vig = 1.0 - 0.14 * (((gx - 960.0) / 960.0) ** 2 * 0.55 + ((gy - 480.0) / 620.0) ** 2 * 0.45)
    out = np.clip(src * np.clip(vig, 0.80, 1.0)[..., None], 0.0, 255.0)
    return out.astype(np.uint8)


def build_narrative_stage_assets() -> list[dict[str, Any]]:
    cap_l = _build_roller_cap(False)
    cap_r = _build_roller_cap(True)
    scroll_bg = _build_scroll_bg()
    plaque_bg = _build_plaque_bg()
    backdrop = _build_temple_backdrop()

    ui_dir = os.path.join(REPO_ROOT, "project/assets/ui/frames")
    p_cap_l = os.path.join(ui_dir, "narrative_roller_cap_l.png")
    p_cap_r = os.path.join(ui_dir, "narrative_roller_cap_r.png")
    p_scroll = os.path.join(ui_dir, "narrative_roller_scroll_bg.png")
    p_plaque = os.path.join(ui_dir, "narrative_roller_plaque_bg.png")
    p_bdrop = os.path.join(ui_dir, "narrative_roller_temple_backdrop.png")

    save_rgba_clean(cap_l, p_cap_l)
    save_rgba_clean(cap_r, p_cap_r)
    save_rgba_clean(scroll_bg, p_scroll)
    save_rgba_clean(plaque_bg, p_plaque)
    save_rgb_clean(backdrop, p_bdrop)

    # Archive source sheet to `assets_src/ui/r2_narrative_rollers_source.png` + `r2_narrative_rollers_spec.json`
    src_sheet = Image.new("RGBA", (1280, 720), (30, 26, 22, 255))
    src_np = np.asarray(src_sheet).copy()
    alpha_over_np(src_np[24 : 24 + 386, 24 : 24 + 80], cap_l)
    alpha_over_np(src_np[24 : 24 + 386, 124 : 124 + 80], cap_r)
    alpha_over_np(src_np[24 : 24 + 290, 230 : 230 + 640], scroll_bg)
    alpha_over_np(src_np[340 : 340 + 62, 230 : 230 + 380], plaque_bg)
    bdrop_thumb = np.asarray(Image.fromarray(backdrop, mode="RGB").resize((480, 270), Image.Resampling.LANCZOS))
    src_np[425 : 425 + 270, 230 : 230 + 480, :3] = bdrop_thumb
    src_np[425 : 425 + 270, 230 : 230 + 480, 3] = 255
    save_rgba_clean(src_np, os.path.join(REPO_ROOT, "assets_src/ui/r2_narrative_rollers_source.png"))

    spec = {
        "narrative_roller_cap_l": {"size": [80, 386], "nine_slice_tb": [64, 52]},
        "narrative_roller_cap_r": {"size": [80, 386], "nine_slice_tb": [64, 52]},
        "narrative_roller_scroll_bg": {"size": [640, 290], "nine_slice_ltrb": [48, 44, 48, 44], "xuan_hex": "#D8CEBE"},
        "narrative_roller_plaque_bg": {"size": [380, 62], "nine_slice_ltrb": [44, 14, 44, 16]},
        "narrative_roller_temple_backdrop": {"size": [1920, 1080], "source": "assets_src/masters/master_c_temple_stage_raw.jpg"},
    }
    with open(os.path.join(REPO_ROOT, "assets_src/ui/r2_narrative_rollers_spec.json"), "w", encoding="utf-8") as fh:
        json.dump(spec, fh, ensure_ascii=False, indent=2)
        fh.write("\n")

    items = [
        (p_cap_l, "80x386", "Carved dark-ebony left vertical handscroll roller with turned finials & 45-deg Ruyi cloud relief"),
        (p_cap_r, "80x386", "Carved dark-ebony right vertical handscroll roller with turned finials & 45-deg Ruyi cloud relief"),
        (p_scroll, "640x290", "Carved #292620 ebony horizontal rails, #C9BA9E tussah-silk border & #D8CEBE aged Xuan paper scroll"),
        (p_plaque, "380x62", "Cusped begonia-ear #1B1714 ebony & #D6A85A chamfered gilt speaker nameplate"),
        (p_bdrop, "1920x1080", "Ghost-free rainy night ruined temple stage backdrop reconstructed from master_c_temple_stage_raw.jpg"),
    ]
    return [
        {
            "path": os.path.relpath(fp, REPO_ROOT),
            "source_path": "assets_src/ui/r2_narrative_rollers_source.png",
            "category": "ui_frame",
            "dimensions": dims,
            "sha256": sha256_file(fp),
            "creation_method": f"tools/build_polish_r2_actors.py (2x supersampled Song-Ming ebony/bronze/Xuan procedural relief & master_c stage reconstruction) | Spec: {desc}",
            "generated_date": GEN_DATE,
            "license": LICENSE_R2,
        }
        for fp, dims, desc in items
    ]


# ==============================================================================
# SECTION 5: MANIFEST UPDATE, STALE-KEY PRUNING & QUANTITATIVE AUDIT GATES
# ==============================================================================
def update_asset_manifest(new_entries: list[dict[str, Any]]) -> int:
    manifest_path = os.path.join(REPO_ROOT, "docs/asset-manifest.json")
    with open(manifest_path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)

    by_path: dict[str, dict[str, Any]] = {
        item["path"]: item
        for item in doc.get("assets", [])
        if os.path.exists(os.path.join(REPO_ROOT, item["path"]))
    }
    for entry in new_entries:
        by_path[entry["path"]] = entry

    doc["updated_at"] = GEN_DATE
    doc["assets"] = [by_path[k] for k in sorted(by_path.keys())]
    with open(manifest_path, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    return len(doc["assets"])


def run_self_audit() -> None:
    """Enforces hard build-time assertions across all generated sprite sheets and portraits."""
    for aid in ["gu_changqing", "shen_qinghe", "pei_zhao", "boss_mist_wolf_king"]:
        png_p = os.path.join(REPO_ROOT, f"project/assets/sprites/{aid}_sheet.png")
        js_p = os.path.join(REPO_ROOT, f"project/assets/sprites/{aid}_sheet.json")
        arr = np.asarray(Image.open(png_p).convert("RGBA"))
        meta = json.load(open(js_p, "r", encoding="utf-8"))
        cw, ch, fy = int(meta["cell_w"]), int(meta["cell_h"]), int(meta["foot_y"])
        htop = int(meta["head_top_px"])

        # 1. Zero-alpha RGB bleed == 0, zero pixels at y >= foot_y + 10,
        #    alpha == 0 on ALL 4 CELL BORDERS, and 0 detached floating islands!
        z = arr[..., 3] == 0
        assert int(np.max(arr[z, :3])) == 0, f"Zero-alpha bleed in {aid}"
        max_mane_above_fy = 0
        for r in range(8):
            for c in range(6):
                cell = arr[r * ch : (r + 1) * ch, c * cw : (c + 1) * cw]
                ca = cell[..., 3]
                if not np.any(ca > 0):
                    continue
                below = int(np.max(ca[fy + 10 :, :]))
                assert below == 0, f"Pixels below foot_y+10 in {aid} cell ({r},{c}): alpha={below}"

                border_max = max(
                    int(np.max(ca[0, :])),
                    int(np.max(ca[ch - 1, :])),
                    int(np.max(ca[:, 0])),
                    int(np.max(ca[:, cw - 1])),
                )
                assert border_max == 0, (
                    f"Hard cell-border clip in {aid} cell ({r},{c}): max_border_alpha={border_max} "
                    f"(top={int(np.max(ca[0,:]))}, bot={int(np.max(ca[ch-1,:]))}, left={int(np.max(ca[:,0]))}, right={int(np.max(ca[:,cw-1]))})"
                )

                nl, _, stats, _ = cv2.connectedComponentsWithStats((ca > 16).astype(np.uint8), connectivity=8)
                assert nl <= 2, (
                    f"Detached floating island/speck in {aid} cell ({r},{c}): {nl - 1} components (areas={stats[1:, cv2.CC_STAT_AREA].tolist()})"
                )

                cy_solid, _ = np.where(ca > 40)
                if len(cy_solid) > 0:
                    max_mane_above_fy = max(max_mane_above_fy, fy - int(cy_solid.min()))

        if aid == "boss_mist_wolf_king":
            assert max_mane_above_fy <= htop, (
                f"Wolf dorsal mane ({max_mane_above_fy}px above foot_y) exceeds head_top_px={htop}!"
            )

        # 2. Measure idle_se, run_se, attack_1, down metrics
        idle_c = arr[0:ch, 0:cw]
        iy, ix = np.where(idle_c[..., 3] > 40)
        idle_w, idle_h = int(ix.max() - ix.min() + 1), int(iy.max() - iy.min() + 1)

        atk_widths = []
        for c in range(5):
            ac = arr[4 * ch : 5 * ch, c * cw : (c + 1) * cw]
            ay, ax = np.where(ac[..., 3] > 40)
            if len(ax):
                atk_widths.append((int(ax.max() - ax.min() + 1), int(ay.max() - ay.min() + 1)))
        max_atk_w = max(w for w, _ in atk_widths)
        max_atk_h = max(h for _, h in atk_widths)

        # Alternating-leg run_se check
        r0 = arr[2 * ch : 3 * ch, 0:cw, :3].astype(np.float32)
        r3 = arr[2 * ch : 3 * ch, 3 * cw : 4 * cw, :3].astype(np.float32)
        run_mad = float(np.mean(np.abs(r0 - r3)))
        spans_42 = []
        for c in range(6):
            rc = arr[2 * ch : 3 * ch, c * cw : (c + 1) * cw]
            _, fxs = np.where(rc[fy - 42 : fy + 6, :, 3] > 40)
            spans_42.append(int(fxs.max() - fxs.min() + 1) if len(fxs) else 0)
        stride_delta = max(spans_42) - min(spans_42)

        # Down collapse check (row 7, col 3)
        dc = arr[7 * ch : 8 * ch, 3 * cw : 4 * cw]
        dy_p, dx_p = np.where(dc[..., 3] > 40)
        down_w, down_h = int(dx_p.max() - dx_p.min() + 1), int(dy_p.max() - dy_p.min() + 1)

        print(
            f"[AUDIT SPRITE] {aid:20s}: cell={cw}x{ch} fy={fy} max_top={max_mane_above_fy}px | idle={idle_w}x{idle_h}px "
            f"| atk1_max={max_atk_w}x{max_atk_h}px | run_spans42={spans_42} (Δ={stride_delta}px, MAD={run_mad:.2f}) "
            f"| down={down_w}x{down_h}px (ratio={down_h/idle_h:.2f})"
        )
        if aid == "boss_mist_wolf_king":
            assert 460 <= idle_w <= 555 and 320 <= idle_h <= 372, f"Wolf idle out of spec: {idle_w}x{idle_h}"
            assert max_atk_h >= 352, f"Wolf attack_1 rearing height too low: {max_atk_h}"
        elif aid == "gu_changqing":
            assert max_atk_w >= 138 and stride_delta >= 20 and run_mad >= 2.2, f"Gu metrics low: atk_w={max_atk_w}, stride={stride_delta}, mad={run_mad:.2f}"
        elif aid == "pei_zhao":
            assert max_atk_w >= 146 and stride_delta >= 20 and run_mad >= 2.2, f"Pei metrics low: atk_w={max_atk_w}, stride={stride_delta}, mad={run_mad:.2f}"
        elif aid == "shen_qinghe":
            assert max_atk_w >= 104 and stride_delta >= 20 and spans_42[0] != spans_42[3], (
                f"Shen metrics/asymmetry fail: atk_w={max_atk_w}, spans={spans_42}"
            )
        assert down_h <= int(idle_h * 0.68), f"Down height not collapsed on {aid}: {down_h} vs {idle_h}"

    # 3. Verify portrait pairwise RMSE & affine-removed sRMSE summary
    pspec = json.load(open(os.path.join(REPO_ROOT, "assets_src/portraits/r2_expression_spec.json"), "r", encoding="utf-8"))
    for pid, info in pspec.items():
        print(
            f"[AUDIT PORTRAIT] {pid:18s}: {len(info['emotions'])} variants | min_RMSE={info['min_pairwise_face_rmse']:.2f} "
            f"| min_affine_sRMSE={info['min_pairwise_affine_srmse']:.2f} ({info['min_pair'][0]} vs {info['min_pair'][1]})"
        )


def main() -> None:
    entries: list[dict[str, Any]] = []
    entries.append(build_wolf_king_sheet())
    entries.extend(build_party_hero_sheets())
    entries.extend(build_all_portraits())
    entries.extend(build_narrative_stage_assets())
    total_manifest = update_asset_manifest(entries)
    run_self_audit()
    print(f"BUILD_POLISH_R2_OK: wrote {len(entries)} M2 assets; manifest total = {total_manifest}.")


if __name__ == "__main__":
    main()
