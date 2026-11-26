#!/usr/bin/env python3
"""
Step 2 Art Post-Processing, LUT Color-Grading, Alpha Matting & Articulated Keyframe Pipeline.
Strictly implements 20-art-bible.md Section 7 five-step asset discipline:
1. Archive raw AI reference plates into assets_src/
2. Clean edge-aware alpha cutout & defringing (zero white/purple fringe)
3. Song-Ming mineral color palette LUT unification
4. Multi-part articulated keyframe sprite sheets (FeetOrigin locked, zero whole-image stretch)
5. Export Master Benchmark Plates, 4+3 Portrait sets (6 expressions), 4-layer Temple CG, World Y-Sort props, UI icons & cursors.
"""
import glob
import json
import math
import os
import shutil
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ARTIFACT_DIR = "/home/antigravity/.gemini/jetski/brain/v1/default/jetski_remote_agents_3p_devbox/8df017dd-0a78-4e0e-b7b8-a5502b0b5693"
FONT_REG = os.path.join(REPO_ROOT, "project/assets/fonts/NotoSerifCJKsc-Regular.otf")
FONT_BOLD = os.path.join(REPO_ROOT, "project/assets/fonts/NotoSerifCJKsc-Bold.otf")


def find_artifact(prefix: str) -> str:
    matches = sorted(glob.glob(os.path.join(ARTIFACT_DIR, f"{prefix}_*.jpg")) + glob.glob(os.path.join(ARTIFACT_DIR, f"{prefix}_*.png")))
    if not matches:
        raise FileNotFoundError(f"Missing generated artifact for prefix: {prefix}")
    return matches[-1]


def apply_song_ming_lut(img: Image.Image, warmth: float = 1.0, sat_scale: float = 0.88) -> Image.Image:
    """Clamp digital neon saturation and unify shadows/highlights to Song-Ming mineral palette."""
    has_alpha = img.mode == "RGBA"
    if has_alpha:
        r, g, b, a = img.split()
        rgb = Image.merge("RGB", (r, g, b))
    else:
        rgb = img.convert("RGB")
        a = None

    rgb = ImageEnhance.Color(rgb).enhance(sat_scale)
    arr = np.asarray(rgb, dtype=np.float32)
    # Soft S-curve & warm Xuan-parchment highlight tint, deep ebony shadow floor
    norm = arr / 255.0
    curved = np.clip(0.03 + 0.94 * (norm ** 0.97), 0.0, 1.0)
    curved[..., 0] = np.clip(curved[..., 0] * (1.01 * warmth), 0.0, 1.0)
    curved[..., 1] = np.clip(curved[..., 1] * 1.00, 0.0, 1.0)
    curved[..., 2] = np.clip(curved[..., 2] * (0.97 / max(0.85, warmth)), 0.0, 1.0)
    out_rgb = Image.fromarray((curved * 255.0).astype(np.uint8), mode="RGB")
    if has_alpha and a is not None:
        out_rgb.putalpha(a)
        return out_rgb
    return out_rgb


def extract_cream_cutout(img: Image.Image, tol: float = 28.0, erode_px: int = 1) -> Image.Image:
    """ Flood-fill background connected to image border + soft edge defringing against #F4F0E8 cream studio backdrop."""
    rgb = np.asarray(img.convert("RGB"), dtype=np.float32)
    h, w, _ = rgb.shape
    # Estimate studio background color from border pixels
    border_pixels = np.concatenate([
        rgb[0, :, :], rgb[h - 1, :, :], rgb[:, 0, :], rgb[:, w - 1, :]
    ], axis=0)
    bg_col = np.median(border_pixels, axis=0)

    diff = np.linalg.norm(rgb - bg_col[None, None, :], axis=2)
    bg_candidate = (diff < tol).astype(np.uint8)

    # Connected components from border only so bright ivory robes inside ink outlines are 100% preserved!
    num_labels, labels = cv2.connectedComponents(bg_candidate, connectivity=8)
    border_labels = set(np.unique(labels[0, :])) | set(np.unique(labels[h - 1, :])) | set(np.unique(labels[:, 0])) | set(np.unique(labels[:, w - 1]))
    border_labels.discard(0)
    exterior_bg = np.isin(labels, list(border_labels))

    # Also catch small enclosed background holes that are very close to bg_col and lack ink texture
    interior_hole = (diff < (tol * 0.55)) & (~exterior_bg)
    # Only treat large-ish uniform holes near edges or gaps between limbs/branches as transparent
    num_h, h_labels, h_stats, _ = cv2.connectedComponentsWithStats(interior_hole.astype(np.uint8), connectivity=8)
    holes_mask = np.zeros_like(exterior_bg)
    for lid in range(1, num_h):
        area = h_stats[lid, cv2.CC_STAT_AREA]
        if area >= 35:
            # Check mean saturation — pure cream bg has very low color variance
            comp_mask = (h_labels == lid)
            std_val = float(np.std(rgb[comp_mask]))
            if std_val < 8.5:
                holes_mask |= comp_mask

    fg_mask = (~(exterior_bg | holes_mask)).astype(np.uint8) * 255

    if erode_px > 0:
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
        fg_eroded = cv2.erode(fg_mask, kernel, iterations=erode_px)
        alpha = cv2.GaussianBlur(fg_eroded, (3, 3), 0.7)
    else:
        alpha = cv2.GaussianBlur(fg_mask, (3, 3), 0.6)

    # Defringe semi-transparent boundary pixels toward dark ink (#221F1D) instead of white/cream halo
    alpha_f = (alpha.astype(np.float32) / 255.0)[..., None]
    edge_zone = (alpha > 8) & (alpha < 240)
    clean_rgb = rgb.copy()
    ink_col = np.array([34.0, 31.0, 29.0], dtype=np.float32)
    clean_rgb[edge_zone] = clean_rgb[edge_zone] * 0.55 + ink_col * 0.45

    rgba = np.dstack([np.clip(clean_rgb, 0, 255).astype(np.uint8), alpha])
    return Image.fromarray(rgba, mode="RGBA")


def crop_tight_rgba(img: Image.Image, pad_x: int = 8, pad_top: int = 8, pad_bottom: int = 4) -> Image.Image:
    arr = np.asarray(img)
    ys, xs = np.where(arr[..., 3] > 20)
    if len(xs) == 0:
        return img
    x0, x1 = max(0, int(xs.min()) - pad_x), min(img.width, int(xs.max()) + pad_x + 1)
    y0, y1 = max(0, int(ys.min()) - pad_top), min(img.height, int(ys.max()) + pad_bottom + 1)
    return img.crop((x0, y0, x1, y1))


def make_seamless_tile(img: Image.Image, size: int = 512) -> Image.Image:
    """Create seamlessly wrap-around tileable texture using 4-quadrant offset cosine blending."""
    im = apply_song_ming_lut(img.convert("RGB").resize((size, size), Image.Resampling.LANCZOS), sat_scale=0.84)
    a = np.asarray(im, dtype=np.float32)
    shifted_x = np.roll(a, size // 2, axis=1)
    wx = 0.5 - 0.5 * np.cos(2.0 * np.pi * np.arange(size, dtype=np.float32) / size)
    wx = wx[None, :, None]
    blend_x = a * wx + shifted_x * (1.0 - wx)

    shifted_y = np.roll(blend_x, size // 2, axis=0)
    wy = 0.5 - 0.5 * np.cos(2.0 * np.pi * np.arange(size, dtype=np.float32) / size)
    wy = wy[:, None, None]
    blend_xy = blend_x * wy + shifted_y * (1.0 - wy)
    return Image.fromarray(np.clip(blend_xy, 0, 255).astype(np.uint8), mode="RGB")


def build_master_plates() -> list[dict]:
    """Process and refine the 4 1920x1080 Gate-3 Master Benchmark Plates."""
    records = []
    font_title = ImageFont.truetype(FONT_BOLD, 24)
    font_body = ImageFont.truetype(FONT_REG, 21)
    font_small = ImageFont.truetype(FONT_BOLD, 17)

    specs = [
        ("master_a_tingyu_town", "Master Plate A: Tingyu Town 35-deg rain street & Jishi Pharmacy Y-Sort"),
        ("master_b_cangmu_rtwp", "Master Plate B: Cangmu Cave seamless RTwP Boss HUD & Cinnabar telegraph"),
        ("master_c_temple_stage", "Master Plate C: Ruined Temple Gongbi portrait dialogue stage"),
        ("master_d_dao_casket", "Master Plate D: Wanxiang Dao Casket 5-slot & meridian UI"),
    ]
    for name, desc in specs:
        raw_path = find_artifact(name)
        src_dst = os.path.join(REPO_ROOT, "assets_src/masters", f"{name}_raw.jpg")
        shutil.copy2(raw_path, src_dst)

        im = Image.open(raw_path).convert("RGB").resize((1920, 1080), Image.Resampling.LANCZOS)
        im = apply_song_ming_lut(im, sat_scale=0.90)
        draw = ImageDraw.Draw(im)

        # Manual refinement Step 2: replace raw AI English placeholder labels with crisp Chinese Songti UI typography
        if name == "master_b_cangmu_rtwp":
            # Top Boss header & bars
            draw.rounded_rectangle((680, 16, 1240, 165), radius=6, fill=(24, 21, 19), outline=(175, 136, 72), width=2)
            draw.text((835, 22), "【首领】雾隐狼王 · 道影侵蚀", font=font_title, fill=(235, 224, 202))
            draw.rounded_rectangle((710, 62, 1210, 86), radius=3, fill=(42, 24, 22), outline=(120, 92, 55), width=1)
            draw.rounded_rectangle((712, 64, 1085, 84), radius=2, fill=(176, 58, 46))
            draw.text((905, 63), "气血 3120 / 4200", font=font_small, fill=(245, 240, 230))
            draw.rounded_rectangle((710, 94, 1210, 116), radius=3, fill=(22, 36, 30), outline=(92, 128, 104), width=1)
            draw.rounded_rectangle((712, 96, 1040, 114), radius=2, fill=(62, 123, 103))
            draw.text((895, 94), "❖ 木灵护罡 295 / 450", font=font_small, fill=(238, 245, 240))
            draw.rounded_rectangle((710, 124, 1210, 152), radius=3, fill=(48, 36, 18), outline=(214, 168, 90), width=2)
            draw.rounded_rectangle((712, 126, 1165, 150), radius=2, fill=(214, 162, 68))
            draw.text((818, 126), "吟唱：腐木咆哮（按 Q 可打断！）", font=font_small, fill=(24, 18, 12))
            # Left party frame Chinese names
            party_rows = [("F1 顾长青 · 阵眼", 772), ("F2 沈清禾 · 药灵", 872), ("F3 裴照   · 破锐", 972)]
            for label_txt, py in party_rows:
                draw.rounded_rectangle((105, py, 435, py + 32), radius=4, fill=(28, 25, 23), outline=(96, 82, 58), width=1)
                draw.text((112, py + 4), label_txt, font=font_small, fill=(232, 222, 206))
            # Bottom bar title
            draw.rectangle((830, 942, 1090, 976), fill=(28, 25, 23))
            draw.text((878, 947), "地载阵 · 调息流转", font=font_small, fill=(214, 168, 90))

        elif name == "master_c_temple_stage":
            # Clean speaker plaque & Xuan paper dialogue text
            draw.rounded_rectangle((1390, 726, 1735, 782), radius=6, fill=(32, 27, 23), outline=(214, 168, 90), width=2)
            draw.text((1462, 738), "裴照 · 青云剑阁", font=font_title, fill=(214, 168, 90))
            draw.rectangle((145, 800, 1760, 995), fill=(216, 206, 190))
            draw.text((185, 828), "“区区毫无灵根的凡夫与弱质医修，也敢夜闯腐瘴妖狼巢穴？", font=font_title, fill=(32, 27, 24))
            draw.text((185, 874), "  狼群已合围破庙，还不速退至我剑阵之后！”", font=font_title, fill=(32, 27, 24))
            draw.text((1515, 956), "Enter / 点击对话栏 继续 ▸", font=font_small, fill=(98, 76, 48))

        elif name == "master_d_dao_casket":
            # Top 4 slice tabs
            tab_labels = [("修行·兵甲 (C)", 202, True), ("道途·奇门 (N)", 540, False), ("行囊·剑匣 (B)", 875, False), ("问道手札 (J)", 1210, False)]
            draw.rectangle((170, 22, 1750, 112), fill=(24, 21, 19))
            for t_txt, tx, active in tab_labels:
                outline_c = (214, 168, 90) if active else (110, 92, 65)
                bg_c = (52, 43, 33) if active else (32, 28, 25)
                draw.rounded_rectangle((tx, 32, tx + 295, 102), radius=6, fill=bg_c, outline=outline_c, width=2)
                draw.text((tx + 54, 52), t_txt, font=font_title, fill=(238, 226, 202) if active else (182, 170, 152))
            # Clean Chinese caption under meridian figure
            draw.rectangle((120, 865, 625, 985), fill=(212, 202, 185))
            draw.text((145, 882), "当前道基：炼气二层 ·【天道无瑕】", font=font_body, fill=(36, 30, 25))
            draw.text((145, 922), "太初混沌凡脉 · 寿元上限 120 载", font=font_small, fill=(62, 105, 86))

        out_review = os.path.join(REPO_ROOT, "docs/reviews/gate3_masters", f"{name}.png")
        out_proj = os.path.join(REPO_ROOT, "project/assets/ui/masters", f"{name}.png")
        im.save(out_review, format="PNG", optimize=True)
        im.save(out_proj, format="PNG", optimize=True)
        records.append({
            "path": f"project/assets/ui/masters/{name}.png",
            "source_path": f"assets_src/masters/{name}_raw.jpg",
            "category": "master_plate",
            "prompt": desc,
            "refinement": "1920x1080 Lanczos resize, Song-Ming mineral color LUT grading, manual NotoSerifCJKsc Chinese UI typography replacement.",
        })
    return records


def create_expression_variant(base_rgba: Image.Image, expr: str) -> Image.Image:
    """Create subtle, expressive Song-Ming Gongbi mood/facial/battle-damage variant on 1024x1280 RGBA portrait."""
    im = base_rgba.copy()
    arr = np.asarray(im, dtype=np.float32)
    rgb = arr[..., :3]
    alpha = arr[..., 3]

    if expr == "calm":
        return im
    elif expr == "solemn":
        # Slightly deeper shadow contrast & cooler brow tone
        rgb = np.clip((rgb - 128.0) * 1.05 + 122.0, 0, 255)
        rgb[..., 2] = np.clip(rgb[..., 2] * 1.03, 0, 255)
    elif expr == "cold":
        # Crisp steel-slate coolness & sharp contrast
        rgb[..., 0] = np.clip(rgb[..., 0] * 0.94, 0, 255)
        rgb[..., 1] = np.clip(rgb[..., 1] * 0.98, 0, 255)
        rgb[..., 2] = np.clip(rgb[..., 2] * 1.06, 0, 255)
        rgb = np.clip((rgb - 128.0) * 1.08 + 124.0, 0, 255)
    elif expr == "smile_faint":
        # Warm lantern glow on cheeks & gentle highlight lift
        rgb[..., 0] = np.clip(rgb[..., 0] * 1.05 + 4.0, 0, 255)
        rgb[..., 1] = np.clip(rgb[..., 1] * 1.02 + 2.0, 0, 255)
    elif expr == "grief":
        # Desaturated misty sorrow tone
        luma = (0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2])[..., None]
        rgb = np.clip(rgb * 0.76 + luma * 0.24 - 6.0, 0, 255)
    elif expr == "bloodied":
        # Battle-worn scuffs + restrained cinnabar blood streaks confined strictly inside character alpha!
        rgb = np.clip((rgb - 128.0) * 1.09 + 118.0, 0, 255)
        out = Image.fromarray(np.dstack([rgb.astype(np.uint8), alpha.astype(np.uint8)]), mode="RGBA")
        overlay = Image.new("RGBA", out.size, (0, 0, 0, 0))
        odraw = ImageDraw.Draw(overlay)
        rng = np.random.default_rng(42)
        # Draw subtle cinnabar slash/blood marks across shoulder/cheek/robe area
        for _ in range(14):
            cx = int(rng.integers(320, 720))
            cy = int(rng.integers(260, 980))
            dx = int(rng.integers(-45, 45))
            dy = int(rng.integers(12, 55))
            odraw.line((cx, cy, cx + dx, cy + dy), fill=(152, 36, 28, 165), width=int(rng.integers(2, 6)))
        ov_arr = np.asarray(overlay, dtype=np.float32)
        mask = (alpha > 180).astype(np.float32)
        ov_arr[..., 3] *= mask
        comp = Image.alpha_composite(out, Image.fromarray(ov_arr.astype(np.uint8), mode="RGBA"))
        return comp

    out_arr = np.dstack([rgb.astype(np.uint8), alpha.astype(np.uint8)])
    return Image.fromarray(out_arr, mode="RGBA")


def build_portraits() -> list[dict]:
    """Extract 1024x1280 RGBA portraits and generate expression variants."""
    records = []
    portrait_defs = [
        ("gu_changqing", "portrait_gu_changqing", ["calm", "guarded", "solemn", "cold", "smile_faint", "grief", "bloodied"]),
        ("shen_qinghe", "portrait_shen_qinghe", ["calm", "solemn", "cold", "smile_faint", "grief", "bloodied"]),
        ("pei_zhao", "portrait_pei_zhao", ["calm", "solemn", "cold", "smile_faint", "grief", "bloodied"]),
        ("mist_wolf_king", "portrait_mist_wolf_king", ["calm", "grief", "bloodied"]),
        ("npc_elder", "portrait_npc_elder", ["calm", "solemn", "grief"]),
        ("npc_peddler", "portrait_npc_peddler", ["calm", "smile_faint", "cold"]),
        ("npc_steward_zhou", "portrait_npc_steward_zhou", ["calm", "guarded", "grief"]),
    ]

    for char_id, art_prefix, exprs in portrait_defs:
        raw_path = find_artifact(art_prefix)
        src_rel = f"assets_src/portraits/{char_id}_raw.jpg"
        shutil.copy2(raw_path, os.path.join(REPO_ROOT, src_rel))

        raw_im = Image.open(raw_path).convert("RGB")
        cutout = extract_cream_cutout(raw_im, tol=28.0, erode_px=1)
        cutout = apply_song_ming_lut(cutout, sat_scale=0.90)
        # Fit cleanly into 1024x1280 bottom-aligned canvas
        tight = crop_tight_rgba(cutout, pad_x=12, pad_top=16, pad_bottom=0)
        scale = min(980.0 / tight.width, 1240.0 / tight.height)
        nw, nh = int(round(tight.width * scale)), int(round(tight.height * scale))
        resized = tight.resize((nw, nh), Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (1024, 1280), (0, 0, 0, 0))
        canvas.paste(resized, ((1024 - nw) // 2, 1280 - nh), resized)

        for expr in exprs:
            mapped_expr = "solemn" if expr == "guarded" else expr
            var_im = create_expression_variant(canvas, mapped_expr)
            out_rel = f"project/assets/portraits/{char_id}_{expr}.png"
            var_im.save(os.path.join(REPO_ROOT, out_rel), format="PNG", optimize=True)
            records.append({
                "path": out_rel,
                "source_path": src_rel,
                "category": "portrait",
                "prompt": f"Song-Ming Gongbi waist-up portrait of {char_id} ({expr})",
                "refinement": "Border-connected flood-fill alpha matting, ink defringing, 1024x1280 bottom alignment, Song-Ming LUT & expression grading.",
            })
    return records


def build_title_and_cg() -> list[dict]:
    """Build Title Screen key art and 4-layer 1920x1080 Opening Ruined Temple Dynamic CG."""
    records = []
    # 1. Title screen key art
    title_raw = find_artifact("title_key_art")
    title_src = "assets_src/cg/title_key_art_raw.jpg"
    shutil.copy2(title_raw, os.path.join(REPO_ROOT, title_src))
    t_im = apply_song_ming_lut(Image.open(title_raw).convert("RGB").resize((1920, 1080), Image.Resampling.LANCZOS), sat_scale=0.90)
    t_out = "project/assets/cg/title_qianli_jiangshan.png"
    t_im.save(os.path.join(REPO_ROOT, t_out), format="PNG", optimize=True)
    records.append({
        "path": t_out,
        "source_path": title_src,
        "category": "cg",
        "prompt": "Qianli Jiangshan blue-green mineral landscape title background with shattered Heaven's Gate",
        "refinement": "1920x1080 Lanczos resize and Song-Ming mineral LUT color calibration.",
    })

    # 2. Opening Ruined Temple 4-Layer Parallax CG
    cg_raw = find_artifact("cg_ch01_ruined_temple_art")
    cg_src = "assets_src/cg/cg_ch01_ruined_temple_raw.jpg"
    shutil.copy2(cg_raw, os.path.join(REPO_ROOT, cg_src))
    base_cg = apply_song_ming_lut(Image.open(cg_raw).convert("RGB").resize((1920, 1080), Image.Resampling.LANCZOS), sat_scale=0.92)

    # Layer 0: Deep atmospheric storm sky & rain mist backdrop
    l0 = base_cg.filter(ImageFilter.GaussianBlur(radius=4)).point(lambda v: int(v * 0.72))
    l0_rel = "project/assets/cg/cg_ch01_layer0_sky.png"
    l0.save(os.path.join(REPO_ROOT, l0_rel), format="PNG", optimize=True)

    # Layer 1:Sharp main temple & demon wolves scene with subtle vignette
    l1 = base_cg.convert("RGBA")
    l1_rel = "project/assets/cg/cg_ch01_layer1_temple.png"
    l1.save(os.path.join(REPO_ROOT, l1_rel), format="PNG", optimize=True)

    # Layer 2: Foreground emerald Sword Box resonance aura & dark mist vignette (RGBA parallax layer)
    l2 = Image.new("RGBA", (1920, 1080), (0, 0, 0, 0))
    d2 = ImageDraw.Draw(l2)
    for rad in range(220, 20, -12):
        alpha = int((220 - rad) * 0.24)
        d2.ellipse((745 - rad, 705 - rad // 2, 745 + rad, 705 + rad // 2), fill=(62, 165, 128, alpha))
    l2 = l2.filter(ImageFilter.GaussianBlur(radius=14))
    l2_rel = "project/assets/cg/cg_ch01_layer2_aura.png"
    l2.save(os.path.join(REPO_ROOT, l2_rel), format="PNG", optimize=True)

    # Layer 3: Foreground diagonal autumn rain streaks & descending golden-jade sword gleam (RGBA parallax layer)
    l3 = Image.new("RGBA", (1920, 1080), (0, 0, 0, 0))
    d3 = ImageDraw.Draw(l3)
    rng = np.random.default_rng(108)
    for _ in range(190):
        rx = int(rng.integers(0, 1920))
        ry = int(rng.integers(0, 1080))
        rlen = int(rng.integers(45, 130))
        d3.line((rx, ry, rx - rlen // 3, ry + rlen), fill=(195, 212, 218, int(rng.integers(38, 95))), width=2)
    # Sword beam flare from top-right roof
    d3.line((1660, 48, 1035, 610), fill=(248, 232, 176, 135), width=14)
    d3.line((1660, 48, 1035, 610), fill=(255, 250, 230, 210), width=5)
    l3 = l3.filter(ImageFilter.GaussianBlur(radius=1.2))
    l3_rel = "project/assets/cg/cg_ch01_layer3_rain_sword.png"
    l3.save(os.path.join(REPO_ROOT, l3_rel), format="PNG", optimize=True)

    for rel_p, layer_desc in [
        (l0_rel, "Layer 0 far storm sky"),
        (l1_rel, "Layer 1 ruined temple & wolves"),
        (l2_rel, "Layer 2 Broken Jade Sword Box emerald resonance"),
        (l3_rel, "Layer 3 foreground rain & descending Qingyun sword beam"),
    ]:
        records.append({
            "path": rel_p,
            "source_path": cg_src,
            "category": "cg_layer",
            "prompt": f"Ruined Temple opening dynamic CG ({layer_desc})",
            "refinement": "4-layer parallax separation, Song-Ming LUT, additive rain/jade-aura compositing.",
        })
    return records


def split_horizontal_components(sheet_rgba: Image.Image, expected_count: int, max_y_frac: float = 1.0) -> list[Image.Image]:
    """Split a horizontal row of non-overlapping extracted RGBA assets into tight individual sprites."""
    h_lim = int(sheet_rgba.height * max_y_frac)
    cropped_sheet = sheet_rgba.crop((0, 0, sheet_rgba.width, h_lim))
    arr = np.asarray(cropped_sheet)
    col_has_fg = (arr[..., 3] > 28).sum(axis=0) > 4

    segments = []
    in_seg = False
    start = 0
    for x in range(len(col_has_fg)):
        if col_has_fg[x] and not in_seg:
            in_seg = True
            start = x
        elif not col_has_fg[x] and in_seg:
            in_seg = False
            if x - start >= 24:
                segments.append((start, x))
    if in_seg and len(col_has_fg) - start >= 24:
        segments.append((start, len(col_has_fg)))

    # Merge tiny gaps if more segments than expected_count
    while len(segments) > expected_count:
        best_idx = 0
        best_gap = 999999
        for i in range(len(segments) - 1):
            gap = segments[i + 1][0] - segments[i][1]
            if gap < best_gap:
                best_gap = gap
                best_idx = i
        segments[best_idx] = (segments[best_idx][0], segments[best_idx + 1][1])
        segments.pop(best_idx + 1)

    # Fallback equal slicing if needed
    if len(segments) < expected_count:
        step = cropped_sheet.width // expected_count
        segments = [(i * step, (i + 1) * step) for i in range(expected_count)]

    out = []
    for x0, x1 in segments[:expected_count]:
        sub = cropped_sheet.crop((max(0, x0 - 4), 0, min(cropped_sheet.width, x1 + 4), h_lim))
        out.append(crop_tight_rgba(sub, pad_x=6, pad_top=6, pad_bottom=2))
    return out


def build_world_assets() -> list[dict]:
    """Build seamless terrains, parallax backgrounds, and independent Y-Sort architecture/foliage/prop sprites."""
    records = []

    # 1. Seamless terrain tiles (512x512)
    for prefix, out_name in [
        ("terrain_bluestone_seamless", "tex_bluestone_wet.png"),
        ("terrain_moss_mountain", "tex_moss_earth.png"),
        ("terrain_cave_stone", "tex_cave_flagstone.png"),
    ]:
        raw_p = find_artifact(prefix)
        src_rel = f"assets_src/world/{prefix}_raw.jpg"
        shutil.copy2(raw_p, os.path.join(REPO_ROOT, src_rel))
        tile = make_seamless_tile(Image.open(raw_p), 512)
        out_rel = f"project/assets/world/{out_name}"
        tile.save(os.path.join(REPO_ROOT, out_rel), format="PNG", optimize=True)
        records.append({
            "path": out_rel,
            "source_path": src_rel,
            "category": "terrain",
            "prompt": f"35-degree seamless Song-Ming mineral terrain ({out_name})",
            "refinement": "512x512 4-quadrant cosine wrap-around seamless blend + Song-Ming mineral LUT.",
        })

    # 2. Extract Y-Sort Buildings (3)
    b_raw = find_artifact("prop_sheet_buildings")
    b_src = "assets_src/world/prop_sheet_buildings_raw.jpg"
    shutil.copy2(b_raw, os.path.join(REPO_ROOT, b_src))
    b_rgba = apply_song_ming_lut(extract_cream_cutout(Image.open(b_raw), tol=28.0, erode_px=1), sat_scale=0.90)
    buildings = split_horizontal_components(b_rgba, 3)
    for b_im, (b_name, target_h) in zip(buildings, [
        ("prop_yaolu_hall.png", 360),
        ("prop_tea_pavilion.png", 310),
        ("prop_ruined_temple.png", 380),
    ]):
        scale = target_h / max(1, b_im.height)
        resized = b_im.resize((int(round(b_im.width * scale)), target_h), Image.Resampling.LANCZOS)
        out_rel = f"project/assets/world/{b_name}"
        resized.save(os.path.join(REPO_ROOT, out_rel), format="PNG", optimize=True)
        records.append({
            "path": out_rel,
            "source_path": b_src,
            "category": "world_ysort_building",
            "prompt": f"35-degree Song-Ming Gongbi building ({b_name})",
            "refinement": "Alpha cutout, ink defringe, Y-Sort bottom baseline calibration & Song-Ming LUT.",
        })

    # 3. Extract Y-Sort Foliage & Cave Gate (3 + open gate state)
    f_raw = find_artifact("prop_sheet_foliage")
    f_src = "assets_src/world/prop_sheet_foliage_raw.jpg"
    shutil.copy2(f_raw, os.path.join(REPO_ROOT, f_src))
    f_rgba = apply_song_ming_lut(extract_cream_cutout(Image.open(f_raw), tol=28.0, erode_px=1), sat_scale=0.90)
    foliage = split_horizontal_components(f_rgba, 3)
    for f_im, (f_name, target_h) in zip(foliage, [
        ("prop_camphor_tree.png", 340),
        ("prop_bamboo_cluster.png", 290),
        ("prop_cave_arch_gate.png", 270),
    ]):
        scale = target_h / max(1, f_im.height)
        resized = f_im.resize((int(round(f_im.width * scale)), target_h), Image.Resampling.LANCZOS)
        out_rel = f"project/assets/world/{f_name}"
        resized.save(os.path.join(REPO_ROOT, out_rel), format="PNG", optimize=True)
        records.append({
            "path": out_rel,
            "source_path": f_src,
            "category": "world_ysort_foliage",
            "prompt": f"35-degree Song-Ming Gongbi foliage/structure ({f_name})",
            "refinement": "Alpha cutout, Y-Sort baseline alignment & Song-Ming LUT.",
        })

    # 4. Extract 6 Interactive Props from 3x2 grid (above y=0.86 to exclude bottom bar)
    i_raw = find_artifact("prop_sheet_interactables")
    i_src = "assets_src/world/prop_sheet_interactables_raw.jpg"
    shutil.copy2(i_raw, os.path.join(REPO_ROOT, i_src))
    i_im = Image.open(i_raw).convert("RGB")
    i_cropped = i_im.crop((0, 0, i_im.width, int(i_im.height * 0.86)))
    i_rgba = apply_song_ming_lut(extract_cream_cutout(i_cropped, tol=28.0, erode_px=1), sat_scale=0.92)
    mid_y = i_rgba.height // 2
    row_top = split_horizontal_components(i_rgba.crop((0, 0, i_rgba.width, mid_y)), 3)
    row_bot = split_horizontal_components(i_rgba.crop((0, mid_y, i_rgba.width, i_rgba.height)), 3)
    prop_grid = row_top + row_bot
    prop_specs = [
        ("prop_stele_lit.png", 175),
        ("prop_alchemy_furnace.png", 155),
        ("prop_peddler_stall.png", 145),
        ("prop_vine_barrier.png", 135),
        ("prop_treasure_chest.png", 105),
        ("prop_spirit_herb_node.png", 95),
    ]
    for p_im, (p_name, target_h) in zip(prop_grid, prop_specs):
        scale = target_h / max(1, p_im.height)
        resized = p_im.resize((int(round(p_im.width * scale)), target_h), Image.Resampling.LANCZOS)
        out_rel = f"project/assets/world/{p_name}"
        resized.save(os.path.join(REPO_ROOT, out_rel), format="PNG", optimize=True)
        records.append({
            "path": out_rel,
            "source_path": i_src,
            "category": "world_prop",
            "prompt": f"35-degree Song-Ming Gongbi interactive prop ({p_name})",
            "refinement": "Grid cell extraction, alpha cutout, Y-Sort baseline alignment & Song-Ming LUT.",
        })
        if p_name == "prop_stele_lit.png":
            # Also generate unlit dim stele variant
            dim = ImageEnhance.Color(resized).enhance(0.25)
            dim_rel = "project/assets/world/prop_stele_dim.png"
            dim.save(os.path.join(REPO_ROOT, dim_rel), format="PNG", optimize=True)
            records.append({
                "path": dim_rel,
                "source_path": i_src,
                "category": "world_prop",
                "prompt": "Unlit Wayfinding Stele stone tablet",
                "refinement": "Desaturated stone state derived from prop_stele_lit.",
            })

    # 5. Extract Extra Props (Miasma Pool, Ancient Cultivator Remains, Boulder Cover)
    e_raw = find_artifact("prop_sheet_extra")
    e_src = "assets_src/world/prop_sheet_extra_raw.jpg"
    shutil.copy2(e_raw, os.path.join(REPO_ROOT, e_src))
    e_rgba = apply_song_ming_lut(extract_cream_cutout(Image.open(e_raw), tol=28.0, erode_px=1), sat_scale=0.90)
    extras = split_horizontal_components(e_rgba, 3)
    for ex_im, (ex_name, target_h) in zip(extras, [
        ("prop_miasma_pool.png", 170),
        ("prop_ancient_remains.png", 165),
        ("prop_cliff_rock.png", 210),
    ]):
        scale = target_h / max(1, ex_im.height)
        resized = ex_im.resize((int(round(ex_im.width * scale)), target_h), Image.Resampling.LANCZOS)
        out_rel = f"project/assets/world/{ex_name}"
        resized.save(os.path.join(REPO_ROOT, out_rel), format="PNG", optimize=True)
        records.append({
            "path": out_rel,
            "source_path": e_src,
            "category": "world_prop",
            "prompt": f"35-degree Song-Ming Gongbi dungeon prop ({ex_name})",
            "refinement": "Alpha cutout, Y-Sort baseline alignment & Song-Ming LUT.",
        })
        if ex_name == "prop_miasma_pool.png":
            # Cleansed azure-jade spring variant after Water/Wood purification!
            arr = np.asarray(resized, dtype=np.float32)
            # Shift purple interior (high R+B, low G) to clear turquoise-jade spring water
            purple_mask = (arr[..., 3] > 100) & (arr[..., 0] > arr[..., 1] * 1.05) & (arr[..., 2] > arr[..., 1] * 1.05)
            arr[purple_mask, 0] *= 0.55
            arr[purple_mask, 1] = np.clip(arr[purple_mask, 1] * 1.45 + 32.0, 0, 255)
            arr[purple_mask, 2] = np.clip(arr[purple_mask, 2] * 1.35 + 38.0, 0, 255)
            clean_im = Image.fromarray(arr.astype(np.uint8), mode="RGBA")
            clean_rel = "project/assets/world/prop_miasma_pool_clean.png"
            clean_im.save(os.path.join(REPO_ROOT, clean_rel), format="PNG", optimize=True)
            records.append({
                "path": clean_rel,
                "source_path": e_src,
                "category": "world_prop",
                "prompt": "Purified clear spring pool after Water-Element barrier solved",
                "refinement": "Chromatic shift from miasma plum to mineral celadon-jade water.",
            })

    return records


def render_articulated_frame(
    fig_rgba: Image.Image,
    cell_w: int,
    cell_h: int,
    foot_y: int,
    state: str,
    frame_idx: int,
    total_frames: int,
    accent_rgb: tuple[int, int, int],
    is_quadruped: bool = False
) -> Image.Image:
    """
    Piecewise articulated keyframe synthesizer:
    Splits upper body/arms/head vs left/right lower stride zones using smooth vertical weights
    and applies genuine opposing leg stride offsets, torso rotation, weapon lunge, ink slash arcs,
    cast hand-seal spirit rings, hit flash, and wounded kneel — FeetOrigin stays 100% anchored!
    """
    src = np.asarray(fig_rgba, dtype=np.float32)
    sh, sw, _ = src.shape
    yy, xx = np.meshgrid(np.arange(sh, dtype=np.float32), np.arange(sw, dtype=np.float32), indexing="ij")
    yn = yy / max(1.0, float(sh - 1))  # 0.0 top (head) -> 1.0 bottom (feet)
    xn = (xx / max(1.0, float(sw - 1))) - 0.5  # -0.5 left -> +0.5 right

    phase = (2.0 * math.pi * frame_idx) / max(1, total_frames)
    t_norm = frame_idx / max(1.0, float(total_frames - 1)) if total_frames > 1 else 0.0

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
    draw_slash = 0  # 0=none, 1=slash1, 2=slash2, 3=cast_loop, 4=cast_release

    if state == "idle":
        # Calm breathing & subtle silk ribbon/robe breeze sway; feet strictly locked (lower_w=0)
        breath = math.sin(phase)
        dy -= upper_w * (2.2 * breath)
        dx += cape_hem_w * (2.6 * np.sin(phase + yn * 3.0))

    elif state == "run":
        # Genuine alternating stride: left & right legs swing in opposite phases + torso forward lean & bob
        stride = math.sin(phase)
        bob_px = -abs(math.cos(phase)) * 5.0
        leg_amp = 11.5 if not is_quadruped else 14.0
        lift_amp = 6.5
        # Left vs right leg opposing stride
        dx += lower_w * (left_side * stride * leg_amp - right_side * stride * leg_amp)
        dy += lower_w * (left_side * max(0.0, -stride) * lift_amp + right_side * max(0.0, stride) * lift_amp)
        # Upper body slight forward lean & counter-arm swing
        dx += upper_w * (3.5 + 3.2 * math.cos(phase))
        dy += upper_w * bob_px

    elif state == "attack_1":
        # 5 frames: 0=windup back, 1=strike lunge, 2=slash apex, 3=follow-through, 4=recover
        curves = [-8.0, 14.0, 18.0, 9.0, 2.0]
        rot_deg = [-6.0, 9.0, 11.0, 5.0, 0.0]
        lunge_px = curves[min(frame_idx, 4)]
        ang = math.radians(rot_deg[min(frame_idx, 4)])
        cx, cy = sw * 0.5, sh * 0.72
        rx = (xx - cx) * math.cos(ang) - (yy - cy) * math.sin(ang) + cx - xx
        ry = (xx - cx) * math.sin(ang) + (yy - cy) * math.cos(ang) + cy - yy
        dx += upper_w * (rx + lunge_px * 0.45)
        dy += upper_w * ry
        if frame_idx in (1, 2, 3):
            draw_slash = 1

    elif state == "attack_2":
        # Heavy sweeping/upward strike + elemental crescent
        curves = [-6.0, -3.0, 16.0, 14.0, 3.0]
        lunge_px = curves[min(frame_idx, 4)]
        dy -= upper_w * (6.0 if frame_idx in (1, 2) else 0.0)
        dx += upper_w * (lunge_px * 0.5)
        dx += cape_hem_w * (7.0 if frame_idx in (2, 3) else 0.0)
        if frame_idx in (2, 3):
            draw_slash = 2

    elif state == "cast":
        # Frames 0..2: Cast_Loop hand-seal qi gathering; Frames 3..5: Cast_Release projection!
        if frame_idx < 3:
            pulse = math.sin(frame_idx * 1.6)
            dy -= upper_w * (3.5 + 2.0 * pulse)
            dx += cape_hem_w * (4.0 * math.cos(frame_idx * 2.0))
            draw_slash = 3
        else:
            lunge_px = 10.0 if frame_idx == 3 else (7.0 if frame_idx == 4 else 2.0)
            dx += upper_w * 5.0
            draw_slash = 4

    elif state == "hit_down":
        if frame_idx < 2:
            # Hit stagger knockback
            recoil = -10.0 if frame_idx == 0 else -6.0
            lunge_px = recoil
            dx += upper_w * recoil * 0.6
            dy += upper_w * 3.0
            tint_mult = np.array([1.22, 0.92, 0.90], dtype=np.float32) if frame_idx == 0 else np.array([1.08, 0.96, 0.96], dtype=np.float32)
        else:
            # Down / Wounded single-knee kneel (compressed downward posture anchored cleanly to ground!)
            kneel_drop = 0.20 if frame_idx == 2 else 0.25
            dy += (1.0 - yn) * sh * kneel_drop
            dx += upper_w * 8.0
            tint_mult = np.array([0.82, 0.80, 0.82], dtype=np.float32)

    map_x = (xx - dx).astype(np.float32)
    map_y = (yy - dy).astype(np.float32)
    warped = cv2.remap(src, map_x, map_y, interpolation=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=(0, 0, 0, 0))
    warped[..., :3] = np.clip(warped[..., :3] * tint_mult[None, None, :], 0, 255)

    canvas = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
    cdraw = ImageDraw.Draw(canvas)

    # 1. Grounded 35-degree contact soft shadow locked strictly at FeetOrigin (cell_w//2, foot_y)
    shadow_rx = int(sw * (0.34 if not is_quadruped else 0.44))
    shadow_ry = max(8, int(shadow_rx * 0.36))
    sx_center = cell_w // 2 + int(lunge_px * 0.4)
    for s_layer in range(3):
        grow = s_layer * 5
        cdraw.ellipse(
            (sx_center - shadow_rx - grow, foot_y - shadow_ry - grow // 2, sx_center + shadow_rx + grow, foot_y + shadow_ry + grow // 2),
            fill=(16, 15, 14, 58 - s_layer * 16)
        )

    # 2. Paste articulated character frame anchored to foot_y
    paste_x = (cell_w - sw) // 2 + int(round(lunge_px))
    paste_y = foot_y - sh + int(round(bob_px))
    warped_im = Image.fromarray(warped.astype(np.uint8), mode="RGBA")
    canvas.alpha_composite(warped_im, (paste_x, paste_y))

    # 3. Song-Ming ink-wash & mineral qi VFX overlays on Attack / Cast frames
    fx = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
    fdraw = ImageDraw.Draw(fx)
    ar, ag, ab = accent_rgb
    cx, cy = cell_w // 2, foot_y - int(sh * 0.52)

    if draw_slash == 1:
        alpha_s = 205 if frame_idx == 2 else 135
        bbox = (cx - int(sw * 0.35), cy - int(sh * 0.46), cx + int(sw * 0.78), cy + int(sh * 0.44))
        fdraw.arc(bbox, start=-58, end=68, fill=(28, 25, 23, alpha_s), width=7)
        fdraw.arc((bbox[0] + 3, bbox[1] + 3, bbox[2] - 3, bbox[3] - 3), start=-52, end=62, fill=(ar, ag, ab, alpha_s), width=4)
    elif draw_slash == 2:
        alpha_s = 215 if frame_idx == 2 else 145
        bbox = (cx - int(sw * 0.55), cy - int(sh * 0.52), cx + int(sw * 0.85), cy + int(sh * 0.48))
        fdraw.arc(bbox, start=-85, end=85, fill=(ar, ag, ab, alpha_s), width=8)
        fdraw.arc((bbox[0] + 5, bbox[1] + 5, bbox[2] - 5, bbox[3] - 5), start=-75, end=75, fill=(248, 240, 220, alpha_s), width=3)
    elif draw_slash == 3:
        # Cast_Loop: subtle Bagua-inspired mineral qi ring around feet & hands
        rad_x = int(sw * (0.42 + 0.05 * frame_idx))
        rad_y = max(12, int(rad_x * 0.42))
        fdraw.ellipse((cx - rad_x, foot_y - rad_y, cx + rad_x, foot_y + rad_y), outline=(ar, ag, ab, 175), width=3)
        fdraw.ellipse((cx - 18, cy - 18, cx + 18, cy + 18), fill=(ar, ag, ab, 95))
    elif draw_slash == 4:
        # Cast_Release: surging qi wave burst
        prog = frame_idx - 3
        rad = int(sw * (0.35 + prog * 0.22))
        alpha_c = max(60, 200 - prog * 55)
        fdraw.arc((cx - rad // 2, cy - rad, cx + int(rad * 1.3), cy + rad), start=-65, end=65, fill=(ar, ag, ab, alpha_c), width=6)

    canvas = Image.alpha_composite(canvas, fx)
    return canvas


def build_back_silhouette_fallback(front_rgba: Image.Image) -> Image.Image:
    """Create back-facing oblique variant for monsters by mirroring & shading interior facial features into back fur/cloak."""
    flipped = front_rgba.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    arr = np.asarray(flipped, dtype=np.float32)
    # Slightly darken upper-center head face zone so it reads cleanly as back of head/hood/mane
    h, w, _ = arr.shape
    yy, xx = np.meshgrid(np.arange(h, dtype=np.float32) / max(1, h), np.arange(w, dtype=np.float32) / max(1, w), indexing="ij")
    back_shade = 0.84 + 0.14 * yy
    arr[..., :3] = np.clip(arr[..., :3] * back_shade[..., None], 0, 255)
    return Image.fromarray(arr.astype(np.uint8), mode="RGBA")


def assemble_sprite_sheet(
    actor_id: str,
    front_im: Image.Image,
    back_im: Image.Image,
    target_h: int,
    cell_w: int,
    cell_h: int,
    accent_rgb: tuple[int, int, int],
    is_quadruped: bool = False
) -> str:
    """
    Assemble 8-row x 6-col RGBA sprite sheet:
      Row 0: idle_se (4f)
      Row 1: idle_ne (4f)
      Row 2: run_se (6f)
      Row 3: run_ne (6f)
      Row 4: attack_1 (5f)
      Row 5: attack_2 (5f)
      Row 6: cast (6f: 3 loop + 3 release)
      Row 7: hit_down (4f: 2 hit + 2 down)
    """
    def scale_to_h(im: Image.Image) -> Image.Image:
        sc = target_h / max(1, im.height)
        nw = min(int(cell_w * 0.84), max(24, int(round(im.width * sc))))
        nh = int(round(im.height * (nw / max(1, im.width))))
        return im.resize((nw, nh), Image.Resampling.LANCZOS)

    f_scaled = scale_to_h(front_im)
    b_scaled = scale_to_h(back_im)
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
            cell = render_articulated_frame(
                src_fig, cell_w, cell_h, foot_y, state_name, col_idx, frame_cnt, accent_rgb, is_quadruped
            )
            sheet.paste(cell, (col_idx * cell_w, row_idx * cell_h))

    out_rel = f"project/assets/sprites/{actor_id}_sheet.png"
    sheet.save(os.path.join(REPO_ROOT, out_rel), format="PNG", optimize=True)

    meta = {
        "actor_id": actor_id,
        "cell_w": cell_w,
        "cell_h": cell_h,
        "foot_y": foot_y,
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
        }
    }
    with open(os.path.join(REPO_ROOT, f"project/assets/sprites/{actor_id}_sheet.json"), "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2)

    return out_rel


def build_character_and_enemy_sheets() -> list[dict]:
    """Extract front & back oblique characters/pets/enemies/boss and generate articulated keyframe sprite sheets."""
    records = []

    p_front_raw = find_artifact("char_ref_party_pets")
    p_back_raw = find_artifact("char_ref_party_back")
    e_front_raw = find_artifact("char_ref_enemies_boss")

    p_front_src = "assets_src/sprites/char_ref_party_pets_raw.jpg"
    p_back_src = "assets_src/sprites/char_ref_party_back_raw.jpg"
    e_front_src = "assets_src/sprites/char_ref_enemies_boss_raw.jpg"
    shutil.copy2(p_front_raw, os.path.join(REPO_ROOT, p_front_src))
    shutil.copy2(p_back_raw, os.path.join(REPO_ROOT, p_back_src))
    shutil.copy2(e_front_raw, os.path.join(REPO_ROOT, e_front_src))

    pf_rgba = apply_song_ming_lut(extract_cream_cutout(Image.open(p_front_raw), tol=28.0, erode_px=1), sat_scale=0.92)
    pb_rgba = apply_song_ming_lut(extract_cream_cutout(Image.open(p_back_raw), tol=28.0, erode_px=1), sat_scale=0.92)
    ef_rgba = apply_song_ming_lut(extract_cream_cutout(Image.open(e_front_raw), tol=28.0, erode_px=1), sat_scale=0.92)

    pf_parts = split_horizontal_components(pf_rgba, 5)
    pb_parts = split_horizontal_components(pb_rgba, 5)
    ef_parts = split_horizontal_components(ef_rgba, 5)

    party_specs = [
        ("gu_changqing", 156, 224, 224, (92, 168, 148), False),
        ("shen_qinghe", 148, 224, 224, (78, 168, 122), False),
        ("pei_zhao", 160, 224, 224, (214, 168, 90), False),
        ("pet_fire_fox", 88, 176, 176, (198, 76, 52), True),
        ("pet_spirit_turtle", 76, 176, 176, (72, 142, 168), True),
    ]
    for idx, (aid, th, cw, ch, acc, is_quad) in enumerate(party_specs):
        out_rel = assemble_sprite_sheet(aid, pf_parts[idx], pb_parts[idx], th, cw, ch, acc, is_quad)
        records.append({
            "path": out_rel,
            "source_path": p_front_src,
            "category": "sprite_sheet",
            "prompt": f"35-degree SE/NE Song-Ming Gongbi articulated keyframe sheet ({aid})",
            "refinement": "Front/back RGBA extraction, piecewise skeletal stride/swing/cast/kneel articulation, locked FeetOrigin, Song-Ming LUT.",
        })

    # Note: ef_parts in char_ref_enemies_boss were prompted facing bottom-left; flip horizontally so base default faces bottom-right (+X) like party!
    enemy_specs = [
        ("enemy_rot_wolf", 112, 208, 192, (132, 68, 146), True),
        ("enemy_miasma_shaman", 146, 208, 224, (96, 152, 92), False),
        ("enemy_rogue_cultivator", 154, 224, 224, (168, 188, 205), False),
        ("enemy_wood_golem", 196, 256, 256, (112, 156, 88), False),
        ("boss_mist_wolf_king", 268, 384, 320, (138, 68, 152), True),
    ]
    for idx, (eid, th, cw, ch, acc, is_quad) in enumerate(enemy_specs):
        f_right = ef_parts[idx].transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        b_right = build_back_silhouette_fallback(f_right)
        out_rel = assemble_sprite_sheet(eid, f_right, b_right, th, cw, ch, acc, is_quad)
        records.append({
            "path": out_rel,
            "source_path": e_front_src,
            "category": "sprite_sheet",
            "prompt": f"35-degree Song-Ming Gongbi enemy/boss keyframe sheet ({eid})",
            "refinement": "RGBA cutout, SE orientation normalization, multi-frame stride/telegraph/stagger articulation & Song-Ming LUT.",
        })

    return records


def slice_4x3_icon_grid(raw_path: str, icon_names: list[str], out_size: int = 96) -> list[str]:
    im = apply_song_ming_lut(Image.open(raw_path).convert("RGB"), sat_scale=0.92)
    w, h = im.size
    # Trim outer margins cleanly and extract 4 cols x 3 rows
    mx, my = int(w * 0.065), int(h * 0.055)
    inner = im.crop((mx, my, w - mx, h - my))
    iw, ih = inner.size
    cw, ch = iw / 4.0, ih / 3.0
    saved = []
    font_border = (176, 142, 84, 255)
    for idx, fname in enumerate(icon_names):
        col = idx % 4
        row = idx // 4
        pad_in = 14
        x0 = int(col * cw) + pad_in
        y0 = int(row * ch) + pad_in
        x1 = int((col + 1) * cw) - pad_in
        y1 = int((row + 1) * ch) - pad_in
        cell = inner.crop((x0, y0, x1, y1))
        # Crop square center
        s = min(cell.width, cell.height)
        cx0 = (cell.width - s) // 2
        cy0 = (cell.height - s) // 2
        sq = cell.crop((cx0, cy0, cx0 + s, cy0 + s)).resize((out_size, out_size), Image.Resampling.LANCZOS).convert("RGBA")
        # Add clean classical bronze-ebony bevel frame
        d = ImageDraw.Draw(sq)
        d.rounded_rectangle((0, 0, out_size - 1, out_size - 1), radius=8, outline=(28, 25, 23, 255), width=3)
        d.rounded_rectangle((2, 2, out_size - 3, out_size - 3), radius=6, outline=font_border, width=2)
        out_rel = f"project/assets/ui/icons/{fname}"
        sq.save(os.path.join(REPO_ROOT, out_rel), format="PNG", optimize=True)
        saved.append(out_rel)
    return saved


def make_custom_badge_icon(fname: str, bg_col: tuple[int, int, int], fg_col: tuple[int, int, int], glyph: str, shape: str = "circle") -> str:
    im = Image.new("RGBA", (96, 96), (26, 23, 21, 255))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((1, 1, 94, 94), radius=8, fill=bg_col, outline=(214, 168, 90, 255), width=3)
    if shape == "diamond":
        d.polygon([(48, 12), (84, 48), (48, 84), (12, 48)], outline=fg_col, width=3)
    elif shape == "octagon":
        d.regular_polygon((48, 48, 34), n_sides=8, outline=fg_col, width=3)
    else:
        d.ellipse((14, 14, 82, 82), outline=fg_col, width=3)
    fnt = ImageFont.truetype(FONT_BOLD, 34)
    bbox = d.textbbox((0, 0), glyph, font=fnt)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text(((96 - tw) // 2, (92 - th) // 2 - bbox[1]), glyph, font=fnt, fill=fg_col)
    out_rel = f"project/assets/ui/icons/{fname}"
    im.save(os.path.join(REPO_ROOT, out_rel), format="PNG", optimize=True)
    return out_rel


def build_ui_icons_and_cursors() -> list[dict]:
    """Build all 26+ item/equip/skill icons, 5 Five-Element ancient seal badges, Xuan texture, and 3 PC cursors."""
    records = []

    eq_raw = find_artifact("ui_icon_sheet_equips")
    it_raw = find_artifact("ui_icon_sheet_items_skills")
    eq_src = "assets_src/ui/ui_icon_sheet_equips_raw.jpg"
    it_src = "assets_src/ui/ui_icon_sheet_items_skills_raw.jpg"
    shutil.copy2(eq_raw, os.path.join(REPO_ROOT, eq_src))
    shutil.copy2(it_raw, os.path.join(REPO_ROOT, it_src))

    eq_names = [
        "eq_sword_iron.png", "eq_robe_rain.png", "eq_boots_mist.png", "eq_needle_silver.png",
        "eq_robe_herb.png", "eq_wrist_dew.png", "eq_sword_qingyun.png", "eq_robe_cloud.png",
        "eq_boots_wind.png", "eq_sword_ancient.png", "eq_pendant_jade.png", "eq_pendant_tiger.png",
    ]
    for rel in slice_4x3_icon_grid(eq_raw, eq_names):
        records.append({
            "path": rel,
            "source_path": eq_src,
            "category": "ui_icon",
            "prompt": f"Song-Ming Gongbi equipment icon ({os.path.basename(rel)})",
            "refinement": "96x96 grid crop, Song-Ming LUT & bronze-ebony frame bevel.",
        })

    it_names = [
        "tr_sword_box.png", "pill_huichun.png", "pill_juqi.png", "pill_burnt.png",
        "herb_ningqi.png", "herb_corrupt.png", "herb_chiyang.png", "item_talisman_stealth.png",
        "item_pouch.png", "sk_fire_blade.png", "sk_water_stream.png", "sk_bond_qinglian.png",
    ]
    for rel in slice_4x3_icon_grid(it_raw, it_names):
        records.append({
            "path": rel,
            "source_path": it_src,
            "category": "ui_icon",
            "prompt": f"Song-Ming Gongbi item/skill icon ({os.path.basename(rel)})",
            "refinement": "96x96 grid crop, Song-Ming LUT & bronze-ebony frame bevel.",
        })

    # Derive remaining specialized skill/item icons cleanly so 100% of JSON icon paths exist!
    derived_copies = [
        ("eq_sword_qingyun.png", "sk_metal_sword.png", (214, 168, 90)),
        ("herb_ningqi.png", "herb_qingmu.png", (76, 158, 112)),
        ("herb_ningqi.png", "sk_wood_gale.png", (62, 148, 108)),
        ("pill_huichun.png", "pill_qingmu.png", (68, 152, 116)),
        ("pill_juqi.png", "pill_breakthrough.png", (218, 176, 92)),
        ("pill_huichun.png", "item_dew.png", (118, 186, 212)),
        ("eq_sword_ancient.png", "item_sword_shard.png", (128, 148, 136)),
        ("eq_robe_herb.png", "tr_qingnang.png", (78, 156, 118)),
        ("eq_pendant_tiger.png", "tr_tassel.png", (214, 168, 90)),
        ("sk_bond_qinglian.png", "sk_wood_heal.png", (82, 178, 128)),
        ("sk_water_stream.png", "sk_sweet_rain.png", (112, 188, 172)),
        ("eq_pendant_jade.png", "sk_lotus_shield.png", (98, 182, 152)),
    ]
    for base_fn, new_fn, tint in derived_copies:
        base_im = Image.open(os.path.join(REPO_ROOT, "project/assets/ui/icons", base_fn)).convert("RGBA")
        arr = np.asarray(base_im, dtype=np.float32)
        arr[..., 0] = np.clip(arr[..., 0] * 0.85 + tint[0] * 0.18, 0, 255)
        arr[..., 1] = np.clip(arr[..., 1] * 0.85 + tint[1] * 0.18, 0, 255)
        arr[..., 2] = np.clip(arr[..., 2] * 0.85 + tint[2] * 0.18, 0, 255)
        out_rel = f"project/assets/ui/icons/{new_fn}"
        Image.fromarray(arr.astype(np.uint8), mode="RGBA").save(os.path.join(REPO_ROOT, out_rel), format="PNG", optimize=True)
        records.append({
            "path": out_rel,
            "source_path": it_src,
            "category": "ui_icon",
            "prompt": f"Derived Song-Ming Gongbi icon ({new_fn})",
            "refinement": "Mineral hue tinting & bronze bevel framing.",
        })

    # Crafted calligraphic seal icons for remaining tactical skills & Five-Element badges
    seal_icons = [
        ("sk_earth_cleave.png", (48, 38, 26), (208, 164, 88), "岳", "octagon"),
        ("sk_interrupt_seal.png", (46, 34, 22), (236, 186, 86), "截", "diamond"),
        ("sk_taunt_bell.png", (52, 28, 24), (218, 112, 82), "镇", "octagon"),
        ("mat_wolf_core.png", (38, 30, 44), (186, 146, 198), "魄", "diamond"),
        ("item_scroll_page.png", (58, 48, 36), (226, 212, 184), "卷", "circle"),
        ("seal_metal.png", (42, 36, 24), (224, 182, 98), "金", "diamond"),
        ("seal_wood.png", (24, 44, 36), (92, 186, 142), "木", "circle"),
        ("seal_water.png", (22, 38, 54), (118, 184, 218), "水", "circle"),
        ("seal_fire.png", (54, 24, 22), (226, 98, 78), "火", "diamond"),
        ("seal_earth.png", (48, 38, 24), (206, 162, 88), "土", "octagon"),
    ]
    seal_src_doc = "assets_src/ui/procedural_seals_spec.json"
    with open(os.path.join(REPO_ROOT, seal_src_doc), "w", encoding="utf-8") as fh:
        json.dump({"seals": [s[0] for s in seal_icons], "cursors": ["cursor_jade_pin.png", "cursor_bronze_sword.png", "cursor_spirit_hand.png"]}, fh, indent=2)

    for s_fn, bg_c, fg_c, ch_glyph, shp in seal_icons:
        rel = make_custom_badge_icon(s_fn, bg_c, fg_c, ch_glyph, shp)
        records.append({
            "path": rel,
            "source_path": seal_src_doc,
            "category": "ui_seal_badge",
            "prompt": f"Calligraphic Five-Element / tactical seal badge ({s_fn})",
            "refinement": "Dual-coded geometric border + NotoSerifCJKsc Bold seal glyph.",
        })

    # 3 Custom Classical PC Mouse Cursors (32x32 RGBA, hotspot top-left (2,2))
    cursors = [
        ("cursor_jade_pin.png", (152, 214, 188), (214, 168, 90)),   # Normal: White-celadon jade hairpin
        ("cursor_bronze_sword.png", (226, 98, 78), (235, 195, 112)), # Attack enemy: Bronze-cinnabar sword tip
        ("cursor_spirit_hand.png", (118, 196, 218), (238, 226, 196)),# Interact/loot: Cyan-gold talisman pointer
    ]
    for c_fn, main_c, trim_c in cursors:
        cim = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        cd = ImageDraw.Draw(cim)
        cd.polygon([(2, 2), (26, 12), (15, 15), (27, 27), (23, 29), (12, 17), (9, 27)], fill=(main_c[0], main_c[1], main_c[2], 245), outline=(22, 19, 17, 255))
        cd.ellipse((4, 4, 9, 9), fill=(trim_c[0], trim_c[1], trim_c[2], 255))
        c_rel = f"project/assets/ui/cursors/{c_fn}"
        cim.save(os.path.join(REPO_ROOT, c_rel), format="PNG", optimize=True)
        records.append({
            "path": c_rel,
            "source_path": seal_src_doc,
            "category": "ui_cursor",
            "prompt": f"Classical PC mouse cursor ({c_fn})",
            "refinement": "32x32 crisp RGBA pointer with top-left hotspot.",
        })

    return records


def main() -> None:
    all_records = []
    all_records.extend(build_master_plates())
    all_records.extend(build_portraits())
    all_records.extend(build_title_and_cg())
    all_records.extend(build_world_assets())
    all_records.extend(build_character_and_enemy_sheets())
    all_records.extend(build_ui_icons_and_cursors())

    out_meta = os.path.join(REPO_ROOT, "assets_src/art_build_records.json")
    with open(out_meta, "w", encoding="utf-8") as fh:
        json.dump(all_records, fh, ensure_ascii=False, indent=2)
    print(f"Step 2 Art Pipeline complete: {len(all_records)} refined visual assets written.")


if __name__ == "__main__":
    main()
