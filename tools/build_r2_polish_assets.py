#!/usr/bin/env python3
"""
Round 2 Sprite & Prop Reconstruction Pipeline for 《尘缘问道》 (v0.1.2-slice):
1. Connected-component character isolation + studio floor-shadow stripping (zero equal-grid slicing bleed:
   restores full wolf head on enemy_rot_wolf, removes floating limbs/sword tips on shaman/rogue/golem/fox,
   and restores full hindquarters on boss_mist_wolf_king).
2. Exterior-border-only flood cutout (preserves 100% of Pei Zhao's white-gold silk back robe without holes).
3. Genuine horizontal side-collapse pose on enemy 'down' frames + generous cell widths for zero lunge clipping.
4. High-contrast dormant carved-stone prop_stele_dim.png (unlit dark grooves vs lit cyan runes) + grounded shadows.
5. Updates docs/asset-manifest.json with exact SHA-256 & dimensions.
"""
import hashlib
import json
import math
import os
import sys
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageEnhance

sys.path.insert(0, os.path.dirname(__file__))
from build_step2_assets import (
    REPO_ROOT,
    apply_song_ming_lut,
    build_back_silhouette_fallback,
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


def isolate_sheet_components(
    raw_path: str,
    expected_n: int,
    shadow_y_start: int = 520,
    strip_enclosed_cream: bool = False,
) -> list[Image.Image]:
    """
    Isolate `expected_n` distinct figures left-to-right from a studio reference sheet:
    - Uses exterior-border-only flood fill on white/ivory-robed characters so silk robes never get holes!
    - On dark monster sheets (`strip_enclosed_cream=True`), also clears enclosed cream gaps between legs/arms.
    - Strips painted beige studio cast-shadows on the floor so figures don't carry grey floor halos or bridge gaps.
    """
    im_raw = Image.open(raw_path).convert("RGB")
    rgb_raw = np.asarray(im_raw, dtype=np.float32)
    h, w, _ = rgb_raw.shape

    border = np.concatenate([rgb_raw[0], rgb_raw[-1], rgb_raw[:, 0], rgb_raw[:, -1]], axis=0)
    bg = np.median(border, axis=0)
    diff = np.linalg.norm(rgb_raw - bg[None, None, :], axis=2)
    luma = 0.299 * rgb_raw[..., 0] + 0.587 * rgb_raw[..., 1] + 0.114 * rgb_raw[..., 2]
    sat = rgb_raw.max(axis=2) - rgb_raw.min(axis=2)
    yy = np.arange(h)[:, None]

    # Studio floor cast-shadow: near bottom, low saturation, bright-to-mid luma without dark ink outlines
    is_floor_shadow = (yy > shadow_y_start) & (sat < 28.0) & (luma > 132.0) & (diff < 82.0)
    bg_cand = ((diff < 32.0) | is_floor_shadow).astype(np.uint8)

    num_l, labels = cv2.connectedComponents(bg_cand, connectivity=8)
    b_set = (
        set(np.unique(labels[0, :]))
        | set(np.unique(labels[-1, :]))
        | set(np.unique(labels[:, 0]))
        | set(np.unique(labels[:, -1]))
    )
    b_set.discard(0)
    ext_bg = np.isin(labels, list(b_set))
    if strip_enclosed_cream:
        enclosed_bg = (~ext_bg) & ((diff < 22.0) | is_floor_shadow)
        ext_bg = ext_bg | enclosed_bg
    fg_mask = (~ext_bg).astype(np.uint8)

    # Apply Song-Ming LUT to RGB
    lut_rgb = np.asarray(apply_song_ming_lut(im_raw, sat_scale=0.92), dtype=np.float32)

    num_c, c_labels, stats, centroids = cv2.connectedComponentsWithStats(fg_mask, connectivity=8)
    major = []
    for cid in range(1, num_c):
        area = int(stats[cid, cv2.CC_STAT_AREA])
        if area >= 2500:
            major.append((float(centroids[cid][0]), cid, stats[cid]))
    major.sort(key=lambda t: t[0])
    if len(major) != expected_n:
        raise RuntimeError(f"Expected {expected_n} figures in {raw_path}, got {len(major)}")

    # Assign any tiny detached ink droplets/tassels (area 18..2499) to the nearest major component within 28px
    comp_masks = [c_labels == cid for _, cid, _ in major]
    for cid in range(1, num_c):
        area = int(stats[cid, cv2.CC_STAT_AREA])
        if 18 <= area < 2500:
            cx_s, cy_s = centroids[cid]
            # Check if not studio noise near border
            if 40 < cx_s < w - 40 and 40 < cy_s < h - 40:
                best_i = min(range(expected_n), key=lambda i: abs(cx_s - major[i][0]))
                comp_masks[best_i] |= (c_labels == cid)

    figures: list[Image.Image] = []
    ink_col = np.array([32.0, 29.0, 27.0], dtype=np.float32)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))

    for mask_bool in comp_masks:
        m_u8 = mask_bool.astype(np.uint8) * 255
        eroded = cv2.erode(m_u8, kernel, iterations=1)
        alpha = cv2.GaussianBlur(eroded, (3, 3), 0.65)

        clean_rgb = lut_rgb.copy()
        edge = (alpha > 8) & (alpha < 242)
        clean_rgb[edge] = clean_rgb[edge] * 0.55 + ink_col * 0.45
        clean_rgb[alpha == 0] = 0.0

        ys, xs = np.where(alpha > 16)
        x0, x1 = max(0, int(xs.min()) - 6), min(w, int(xs.max()) + 7)
        y0, y1 = max(0, int(ys.min()) - 6), min(h, int(ys.max()) + 5)
        rgba = np.dstack([np.clip(clean_rgb, 0, 255).astype(np.uint8), alpha])
        figures.append(Image.fromarray(rgba[y0:y1, x0:x1], mode="RGBA"))

    return figures


def render_clean_frame(
    fig_rgba: Image.Image,
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
    src = np.asarray(fig_rgba, dtype=np.float32)
    sh, sw, _ = src.shape

    # Special handling for enemy 'down' (frames 2, 3 of hit_down): genuine defeated collapse onto the ground!
    if is_enemy and state == "hit_down" and frame_idx >= 2:
        collapsed_h = max(20, int(round(sh * 0.46)))
        collapsed_w = min(cell_w - 20, int(round(sw * 1.10)))
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
        cd = ImageDraw.Draw(canvas)
        srx = int(rot_im.width * 0.46)
        sry = max(7, int(srx * 0.28))
        cd.ellipse((cell_w // 2 - srx, foot_y - sry, cell_w // 2 + srx, foot_y + sry), fill=(18, 15, 20, int(65 * fade)))
        px = (cell_w - rot_im.width) // 2
        py = foot_y - rot_im.height + 4
        canvas.alpha_composite(Image.fromarray(np.clip(r_arr, 0, 255).astype(np.uint8), mode="RGBA"), (px, py))
        return canvas

    yy, xx = np.meshgrid(np.arange(sh, dtype=np.float32), np.arange(sw, dtype=np.float32), indexing="ij")
    yn = yy / max(1.0, float(sh - 1))
    xn = (xx / max(1.0, float(sw - 1))) - 0.5

    phase = (2.0 * math.pi * frame_idx) / max(1, total_frames)
    dx = np.zeros_like(xx)
    dy = np.zeros_like(yy)

    upper_w = np.clip(1.0 - (yn - 0.45) / 0.35, 0.0, 1.0)
    lower_w = np.clip((yn - 0.52) / 0.45, 0.0, 1.0)
    left_side = np.clip((-xn + 0.04) * 5.0, 0.0, 1.0)
    right_side = np.clip((xn + 0.04) * 5.0, 0.0, 1.0)
    cape_hem_w = np.clip((yn - 0.35) / 0.55, 0.0, 1.0) * (1.0 - np.clip((yn - 0.88) / 0.12, 0.0, 1.0))

    lunge_px = 0.0
    bob_px = 0.0
    tint_mult = np.array([1.0, 1.0, 1.0], dtype=np.float32)
    draw_slash = 0

    if state == "idle":
        breath = math.sin(phase)
        dy -= upper_w * (2.0 * breath)
        dx += cape_hem_w * (2.2 * np.sin(phase + yn * 3.0))
    elif state == "run":
        stride = math.sin(phase)
        bob_px = -abs(math.cos(phase)) * 4.5
        leg_amp = 10.5 if not is_quadruped else 12.5
        lift_amp = 6.0
        dx += lower_w * (left_side * stride * leg_amp - right_side * stride * leg_amp)
        dy += lower_w * (left_side * max(0.0, -stride) * lift_amp + right_side * max(0.0, stride) * lift_amp)
        dx += upper_w * (3.0 + 2.8 * math.cos(phase))
        dy += upper_w * bob_px
    elif state == "attack_1":
        curves = [-7.0, 12.0, 15.0, 8.0, 2.0]
        rot_deg = [-5.0, 8.0, 10.0, 4.0, 0.0]
        lunge_px = curves[min(frame_idx, 4)]
        ang = math.radians(rot_deg[min(frame_idx, 4)])
        cx0, cy0 = sw * 0.5, sh * 0.72
        rx = (xx - cx0) * math.cos(ang) - (yy - cy0) * math.sin(ang) + cx0 - xx
        ry = (xx - cx0) * math.sin(ang) + (yy - cy0) * math.cos(ang) + cy0 - yy
        dx += upper_w * (rx + lunge_px * 0.4)
        dy += upper_w * ry
        if frame_idx in (1, 2, 3):
            draw_slash = 1
    elif state == "attack_2":
        curves = [-5.0, -2.0, 14.0, 11.0, 2.0]
        lunge_px = curves[min(frame_idx, 4)]
        dy -= upper_w * (5.5 if frame_idx in (1, 2) else 0.0)
        dx += upper_w * (lunge_px * 0.45)
        dx += cape_hem_w * (6.0 if frame_idx in (2, 3) else 0.0)
        if frame_idx in (2, 3):
            draw_slash = 2
    elif state == "cast":
        if frame_idx < 3:
            pulse = math.sin(frame_idx * 1.6)
            dy -= upper_w * (3.2 + 1.8 * pulse)
            dx += cape_hem_w * (3.5 * math.cos(frame_idx * 2.0))
            draw_slash = 3
        else:
            lunge_px = 9.0 if frame_idx == 3 else (6.0 if frame_idx == 4 else 2.0)
            dx += upper_w * 4.5
            draw_slash = 4
    elif state == "hit_down":
        if frame_idx < 2:
            recoil = -9.0 if frame_idx == 0 else -5.0
            lunge_px = recoil
            dx += upper_w * recoil * 0.55
            dy += upper_w * 3.0
            tint_mult = np.array([1.22, 0.90, 0.88], dtype=np.float32) if frame_idx == 0 else np.array([1.08, 0.95, 0.95], dtype=np.float32)
        else:
            kneel_drop = 0.22 if frame_idx == 2 else 0.26
            dy += (1.0 - yn) * sh * kneel_drop
            dx += upper_w * 7.0
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

    canvas = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
    cdraw = ImageDraw.Draw(canvas)

    shadow_rx = int(sw * (0.33 if not is_quadruped else 0.42))
    shadow_ry = max(7, int(shadow_rx * 0.34))
    sx_center = cell_w // 2 + int(lunge_px * 0.35)
    for s_layer in range(3):
        grow = s_layer * 5
        cdraw.ellipse(
            (sx_center - shadow_rx - grow, foot_y - shadow_ry - grow // 2, sx_center + shadow_rx + grow, foot_y + shadow_ry + grow // 2),
            fill=(16, 15, 14, 56 - s_layer * 16),
        )

    paste_x = max(2, min(cell_w - sw - 2, (cell_w - sw) // 2 + int(round(lunge_px))))
    paste_y = max(2, foot_y - sh + int(round(bob_px)))
    canvas.alpha_composite(Image.fromarray(warped.astype(np.uint8), mode="RGBA"), (paste_x, paste_y))

    fx = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
    fdraw = ImageDraw.Draw(fx)
    ar, ag, ab = accent_rgb
    cx, cy = cell_w // 2, foot_y - int(sh * 0.52)

    if draw_slash == 1:
        alpha_s = 205 if frame_idx == 2 else 135
        bbox = (cx - int(sw * 0.32), cy - int(sh * 0.44), min(cell_w - 6, cx + int(sw * 0.72)), cy + int(sh * 0.42))
        fdraw.arc(bbox, start=-58, end=68, fill=(28, 25, 23, alpha_s), width=7)
        fdraw.arc((bbox[0] + 3, bbox[1] + 3, bbox[2] - 3, bbox[3] - 3), start=-52, end=62, fill=(ar, ag, ab, alpha_s), width=4)
    elif draw_slash == 2:
        alpha_s = 215 if frame_idx == 2 else 145
        bbox = (cx - int(sw * 0.48), cy - int(sh * 0.48), min(cell_w - 6, cx + int(sw * 0.78)), cy + int(sh * 0.46))
        fdraw.arc(bbox, start=-82, end=82, fill=(ar, ag, ab, alpha_s), width=8)
        fdraw.arc((bbox[0] + 5, bbox[1] + 5, bbox[2] - 5, bbox[3] - 5), start=-72, end=72, fill=(248, 240, 220, alpha_s), width=3)
    elif draw_slash == 3:
        rad_x = min(cell_w // 2 - 6, int(sw * (0.40 + 0.04 * frame_idx)))
        rad_y = max(11, int(rad_x * 0.40))
        fdraw.ellipse((cx - rad_x, foot_y - rad_y, cx + rad_x, foot_y + rad_y), outline=(ar, ag, ab, 175), width=3)
        fdraw.ellipse((cx - 16, cy - 16, cx + 16, cy + 16), fill=(ar, ag, ab, 92))
    elif draw_slash == 4:
        prog = frame_idx - 3
        rad = int(sw * (0.32 + prog * 0.18))
        alpha_c = max(60, 195 - prog * 55)
        fdraw.arc((cx - rad // 2, cy - rad, min(cell_w - 5, cx + int(rad * 1.2)), cy + rad), start=-62, end=62, fill=(ar, ag, ab, alpha_c), width=6)

    return Image.alpha_composite(canvas, fx)


def build_sheet(
    actor_id: str,
    front_im: Image.Image,
    back_im: Image.Image,
    target_h: int,
    cell_w: int,
    cell_h: int,
    accent_rgb: tuple[int, int, int],
    is_quadruped: bool = False,
    is_enemy: bool = False,
) -> str:
    def scale_fit(im: Image.Image) -> Image.Image:
        sc = target_h / max(1, im.height)
        max_w = int(cell_w * 0.76)  # Leave 24% margin so lunges & weapon tips never clip cell borders!
        nw = min(max_w, max(24, int(round(im.width * sc))))
        nh = int(round(im.height * (nw / max(1, im.width))))
        return im.resize((nw, nh), Image.Resampling.LANCZOS)

    f_scaled = scale_fit(front_im)
    b_scaled = scale_fit(back_im)
    foot_y = cell_h - 22

    sheet = Image.new("RGBA", (cell_w * 6, cell_h * 8), (0, 0, 0, 0))
    row_specs = [
        (0, f_scaled, "idle", 4),
        (1, b_scaled, "idle", 4),
        (2, f_scaled, "run", 6),
        (3, b_scaled, "run", 6),
        (4, f_scaled, "attack_1", 5),
        (5, f_scaled, "attack_2", 5),
        (6, f_scaled, "cast", 6),
        (7, f_scaled, "hit_down", 4),
    ]
    for row_idx, src_fig, state_name, frame_cnt in row_specs:
        for col_idx in range(frame_cnt):
            cell = render_clean_frame(
                src_fig, cell_w, cell_h, foot_y, state_name, col_idx, frame_cnt, accent_rgb, is_quadruped, is_enemy
            )
            sheet.paste(cell, (col_idx * cell_w, row_idx * cell_h))

    out_rel = f"project/assets/sprites/{actor_id}_sheet.png"
    sheet.save(os.path.join(REPO_ROOT, out_rel), format="PNG", optimize=True)

    meta = {
        "actor_id": actor_id,
        "cell_w": cell_w,
        "cell_h": cell_h,
        "foot_y": foot_y,
        "head_top_px": max(72, f_scaled.height + 10),
        "cols": 6,
        "rows": {
            "idle_se": {"row": 0, "frames": 4, "fps": 6.0, "loop": True},
            "idle_ne": {"row": 1, "frames": 4, "fps": 6.0, "loop": True},
            "run_se": {"row": 2, "frames": 6, "fps": 10.0, "loop": True},
            "run_ne": {"row": 3, "frames": 6, "fps": 10.0, "loop": True},
            "attack_1": {"row": 4, "frames": 5, "fps": 11.0, "loop": False},
            "attack_2": {"row": 5, "frames": 5, "fps": 11.0, "loop": False},
            "cast_loop": {"row": 6, "start_col": 0, "frames": 3, "fps": 7.0, "loop": True},
            "cast_release": {"row": 6, "start_col": 3, "frames": 3, "fps": 10.0, "loop": False},
            "hit": {"row": 7, "start_col": 0, "frames": 2, "fps": 9.0, "loop": False},
            "down": {"row": 7, "start_col": 2, "frames": 2, "fps": 4.0, "loop": False},
        },
    }
    with open(os.path.join(REPO_ROOT, f"project/assets/sprites/{actor_id}_sheet.json"), "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2)
    return out_rel


def add_grounded_base_shadow(im: Image.Image, pad_x: int = 18, pad_bot: int = 12) -> Image.Image:
    nw = im.width + pad_x * 2
    nh = im.height + pad_bot
    canvas = Image.new("RGBA", (nw, nh), (0, 0, 0, 0))
    cd = ImageDraw.Draw(canvas)
    for s_i in range(3):
        grow = s_i * 5
        cd.ellipse(
            (pad_x // 2 - grow, nh - 34 - grow // 2, nw - pad_x // 2 + grow, nh - 4 + grow // 2),
            fill=(16, 18, 16, 68 - s_i * 18),
        )
    canvas.alpha_composite(im, (pad_x, 0))
    return canvas


def rebuild_steles_and_furnace() -> list[str]:
    # Extract clean stele & furnace directly from assets_src/world/prop_sheet_interactables_raw.jpg
    raw_p = os.path.join(REPO_ROOT, "assets_src/world/prop_sheet_interactables_raw.jpg")
    im = Image.open(raw_p).convert("RGB")
    top_row = im.crop((0, 0, im.width, int(im.height * 0.43)))
    top_parts = isolate_sheet_components_from_pil(top_row, 3, shadow_y_start=int(top_row.height * 0.78))

    # 0 = stele, 1 = alchemy furnace
    stele_raw, furnace_raw = top_parts[0], top_parts[1]
    sc_s = 172.0 / max(1, stele_raw.height)
    stele_lit_core = stele_raw.resize((int(round(stele_raw.width * sc_s)), 172), Image.Resampling.LANCZOS)
    stele_lit = add_grounded_base_shadow(stele_lit_core, pad_x=18, pad_bot=10)
    lit_rel = "project/assets/world/prop_stele_lit.png"
    stele_lit.save(os.path.join(REPO_ROOT, lit_rel), format="PNG", optimize=True)

    # Build unmistakably unlit dormant weathered stone stele (turn glowing cyan runes into dark carved grooves!)
    s_arr = np.asarray(stele_lit_core, dtype=np.float32).copy()
    rgb = s_arr[..., :3]
    alpha = s_arr[..., 3]
    # Detect cyan/jade glowing pixels (G and B noticeably higher than R, or high luminance inside tablet)
    cyan_glow = (alpha > 30) & ((rgb[..., 1] > rgb[..., 0] + 10.0) | (rgb[..., 2] > rgb[..., 0] + 10.0))
    # Carve glowing runes into deep mossy slate-charcoal grooves (#2F3633)
    rgb[cyan_glow, 0] = rgb[cyan_glow, 0] * 0.34 + 26.0
    rgb[cyan_glow, 1] = rgb[cyan_glow, 1] * 0.30 + 30.0
    rgb[cyan_glow, 2] = rgb[cyan_glow, 2] * 0.30 + 28.0
    # Weather overall stone body slightly cooler & darker so lit vs unlit pops at a glance
    stone_body = (alpha > 30) & (~cyan_glow)
    luma_b = (0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2])[..., None]
    rgb[stone_body] = (rgb[stone_body] * 0.45 + luma_b[stone_body] * 0.55) * 0.76
    stele_dim_core = Image.fromarray(np.dstack([np.clip(rgb, 0, 255).astype(np.uint8), alpha.astype(np.uint8)]), mode="RGBA")
    stele_dim = add_grounded_base_shadow(stele_dim_core, pad_x=18, pad_bot=10)
    dim_rel = "project/assets/world/prop_stele_dim.png"
    stele_dim.save(os.path.join(REPO_ROOT, dim_rel), format="PNG", optimize=True)

    # Grounded shadow on alchemy furnace too
    sc_f = 154.0 / max(1, furnace_raw.height)
    furnace_core = furnace_raw.resize((int(round(furnace_raw.width * sc_f)), 154), Image.Resampling.LANCZOS)
    furnace_out = add_grounded_base_shadow(furnace_core, pad_x=16, pad_bot=10)
    fur_rel = "project/assets/world/prop_alchemy_furnace.png"
    furnace_out.save(os.path.join(REPO_ROOT, fur_rel), format="PNG", optimize=True)

    return [lit_rel, dim_rel, fur_rel]


def isolate_sheet_components_from_pil(im_raw: Image.Image, expected_n: int, shadow_y_start: int) -> list[Image.Image]:
    import tempfile

    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tf:
        tmp_p = tf.name
    try:
        im_raw.save(tmp_p)
        return isolate_sheet_components(tmp_p, expected_n, shadow_y_start=shadow_y_start)
    finally:
        if os.path.exists(tmp_p):
            os.remove(tmp_p)


def main() -> None:
    pf_src = os.path.join(REPO_ROOT, "assets_src/sprites/char_ref_party_pets_raw.jpg")
    pb_src = os.path.join(REPO_ROOT, "assets_src/sprites/char_ref_party_back_raw.jpg")
    ef_src = os.path.join(REPO_ROOT, "assets_src/sprites/char_ref_enemies_boss_raw.jpg")

    pf_figs = isolate_sheet_components(pf_src, 5, shadow_y_start=565, strip_enclosed_cream=False)
    pb_figs = isolate_sheet_components(pb_src, 5, shadow_y_start=565, strip_enclosed_cream=False)
    ef_figs = isolate_sheet_components(ef_src, 5, shadow_y_start=520, strip_enclosed_cream=True)

    updated_paths: list[str] = []

    party_specs = [
        ("gu_changqing", 156, 232, 224, (92, 168, 148), False),
        ("shen_qinghe", 148, 224, 224, (78, 168, 122), False),
        ("pei_zhao", 160, 240, 224, (214, 168, 90), False),
        ("pet_fire_fox", 88, 192, 176, (198, 76, 52), True),
        ("pet_spirit_turtle", 76, 208, 176, (72, 142, 168), True),
    ]
    for i, (aid, th, cw, ch, acc, is_q) in enumerate(party_specs):
        rel = build_sheet(aid, pf_figs[i], pb_figs[i], th, cw, ch, acc, is_quadruped=is_q, is_enemy=False)
        updated_paths.append(rel)

    enemy_specs = [
        ("enemy_rot_wolf", 108, 256, 192, (132, 68, 146), True),
        ("enemy_miasma_shaman", 146, 224, 224, (96, 152, 92), False),
        ("enemy_rogue_cultivator", 154, 240, 224, (168, 188, 205), False),
        ("enemy_wood_golem", 192, 272, 264, (112, 156, 88), False),
        ("boss_mist_wolf_king", 264, 384, 320, (138, 68, 152), True),
    ]
    for i, (eid, th, cw, ch, acc, is_q) in enumerate(enemy_specs):
        f_right = ef_figs[i].transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        b_right = build_back_silhouette_fallback(f_right)
        rel = build_sheet(eid, f_right, b_right, th, cw, ch, acc, is_quadruped=is_q, is_enemy=True)
        updated_paths.append(rel)

    updated_paths.extend(rebuild_steles_and_furnace())

    # Update docs/asset-manifest.json SHA-256 and dimensions for all modified assets
    manifest_p = os.path.join(REPO_ROOT, "docs/asset-manifest.json")
    with open(manifest_p, "r", encoding="utf-8") as fh:
        mdoc = json.load(fh)
    by_path = {e["path"]: e for e in mdoc.get("assets", [])}
    for rel_p in updated_paths:
        abs_p = os.path.join(REPO_ROOT, rel_p)
        with Image.open(abs_p) as im_c:
            dims = f"{im_c.width}x{im_c.height}"
        if rel_p in by_path:
            by_path[rel_p]["dimensions"] = dims
            by_path[rel_p]["sha256"] = sha256_file(abs_p)

    mdoc["assets"] = sorted(by_path.values(), key=lambda x: x["path"])
    with open(manifest_p, "w", encoding="utf-8") as fh:
        json.dump(mdoc, fh, ensure_ascii=False, indent=2)
        fh.write("\n")

    print(f"Successfully rebuilt {len(updated_paths)} sprite sheets & props and synced docs/asset-manifest.json.")


if __name__ == "__main__":
    main()
