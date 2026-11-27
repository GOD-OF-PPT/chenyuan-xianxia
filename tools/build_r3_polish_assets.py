#!/usr/bin/env python3
"""
Round 3 Asset Builder for 《尘缘问道》 (v0.1.3-slice):
1. Build razor-crisp 1024x1024 Song-Ming Gongbi meadow ground texture (tex_moss_earth.png)
   using 80px edge-only overlap-crop seamless wrapping (zero interior blur / zero mosaic haze!).
2. Extract wandering Daoist peddler (npc_peddler_sheet.png + .json), wooden pharmacy counter
   (prop_yaolu_counter.png), and discarded pill basket (prop_discarded_pill_basket.png) with
   strict exterior flood-fill cutout and grounded 35-deg contact shadows.
3. Soft-feather outer root-moss rim of prop_camphor_tree.png so tree roots blend naturally into the meadow.
4. Register all provenance, prompts, licenses, dimensions, and SHA-256 hashes in docs/asset-manifest.json.
"""
import glob
import hashlib
import json
import os
import shutil
import sys
import cv2
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
from build_step2_assets import REPO_ROOT, apply_song_ming_lut, build_back_silhouette_fallback
from build_r2_polish_assets import isolate_sheet_components, build_sheet


ARTIFACT_DIR = "/home/antigravity/.gemini/jetski/brain/v1/default/jetski_remote_agents_3p_devbox/8df017dd-0a78-4e0e-b7b8-a5502b0b5693"


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        while True:
            chunk = fh.read(65536)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def latest_artifact(prefix: str) -> str:
    matches = sorted(glob.glob(os.path.join(ARTIFACT_DIR, f"{prefix}_*.jpg")) + glob.glob(os.path.join(ARTIFACT_DIR, f"{prefix}_*.png")))
    if not matches:
        raise FileNotFoundError(f"No artifact found for {prefix}")
    return matches[-1]


def make_crisp_overlap_seamless(im: Image.Image, out_size: int = 1024, overlap: int = 80) -> Image.Image:
    """
    Create a 100% seamless tile WITHOUT blurring the interior:
    Resizes to (out_size + overlap, out_size + overlap) and smoothstep-blends ONLY the
    `overlap`-px border margin against the opposite overhang strip, keeping >85% of pixels
    100% sharp original Gongbi ink & mineral brushwork.
    """
    big = im.convert("RGB").resize((out_size + overlap, out_size + overlap), Image.Resampling.LANCZOS)
    arr = np.asarray(big, dtype=np.float32).copy()

    t = (np.arange(overlap, dtype=np.float32) + 0.5) / float(overlap)
    s = (t * t * (3.0 - 2.0 * t))  # smoothstep 0 -> 1

    # Horizontal seam along x in [0, overlap)
    sx = s[None, :, None]
    arr[:, :overlap, :] = (1.0 - sx) * arr[:, out_size : out_size + overlap, :] + sx * arr[:, :overlap, :]
    arr = arr[:, :out_size, :]

    # Vertical seam along y in [0, overlap)
    sy = s[:, None, None]
    arr[:overlap, :, :] = (1.0 - sy) * arr[out_size : out_size + overlap, :, :] + sy * arr[:overlap, :]
    arr = arr[:out_size, :, :]

    # Harmonize value & saturation to rainy Song-Ming celadon-olive (#485644 .. #5C6B54)
    # so characters, speech bubbles, and bluestone flagstones read clearly against the meadow
    graded = apply_song_ming_lut(Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode="RGB"), sat_scale=0.82)
    g = np.asarray(graded, dtype=np.float32)
    # Subtle rainy overcast darkening (keeps every ink blade crisp while preventing bright grass glare)
    g[..., 0] = g[..., 0] * 0.78 + 8.0
    g[..., 1] = g[..., 1] * 0.80 + 11.0
    g[..., 2] = g[..., 2] * 0.82 + 12.0
    return Image.fromarray(np.clip(g, 0, 255).astype(np.uint8), mode="RGB")


def save_grounded_prop(fig_rgba: Image.Image, target_h: int, out_rel: str, shadow_alpha: int = 86) -> None:
    sc = target_h / max(1, fig_rgba.height)
    nw = max(24, int(round(fig_rgba.width * sc)))
    nh = max(24, int(round(fig_rgba.height * sc)))
    resized = fig_rgba.resize((nw, nh), Image.Resampling.LANCZOS)

    pad_x = 12
    pad_top = 6
    pad_bot = 8
    cw = nw + pad_x * 2
    ch = nh + pad_top + pad_bot

    # Project the bottom 38% silhouette downward by 4px and blur softly so shadow hugs isometric legs naturally
    r_arr = np.asarray(resized, dtype=np.float32)
    foot_cut = int(nh * 0.62)
    sil = np.zeros((ch, cw), dtype=np.float32)
    sil[pad_top + foot_cut + 3 : pad_top + nh + 3, pad_x : pad_x + nw] = (r_arr[foot_cut:, :, 3] / 255.0) * float(shadow_alpha)
    sil = cv2.GaussianBlur(sil, (15, 9), 4.2)

    sh_rgba = np.zeros((ch, cw, 4), dtype=np.uint8)
    sh_rgba[..., 0] = 16
    sh_rgba[..., 1] = 20
    sh_rgba[..., 2] = 18
    sh_rgba[..., 3] = np.clip(sil, 0, 255).astype(np.uint8)

    canvas = Image.fromarray(sh_rgba, mode="RGBA")
    canvas.alpha_composite(resized, (pad_x, pad_top))
    canvas.save(os.path.join(REPO_ROOT, out_rel), format="PNG", optimize=True)


def feather_camphor_root_rim() -> str:
    rel = "project/assets/world/prop_camphor_tree.png"
    full = os.path.join(REPO_ROOT, rel)
    im = Image.open(full).convert("RGBA")
    arr = np.asarray(im, dtype=np.float32).copy()
    h, w, _ = arr.shape
    # In the bottom 22% (root moss skirt), darken pale moss rim slightly & soften outer 6px alpha transition
    y_start = int(h * 0.78)
    sub_a = arr[y_start:, :, 3]
    dist = cv2.distanceTransform((sub_a > 24).astype(np.uint8), cv2.DIST_L2, 5)
    fade = np.clip(dist / 7.5, 0.0, 1.0)
    arr[y_start:, :, 3] = sub_a * fade
    # Harmonize bright moss pixels at base toward deeper damp moss
    sub_rgb = arr[y_start:, :, :3]
    luma = 0.299 * sub_rgb[..., 0] + 0.587 * sub_rgb[..., 1] + 0.114 * sub_rgb[..., 2]
    bright_mask = (sub_a > 10) & (luma > 118.0)
    sub_rgb[bright_mask] = sub_rgb[bright_mask] * 0.74 + np.array([22.0, 30.0, 24.0], dtype=np.float32) * 0.26
    arr[y_start:, :, :3] = sub_rgb
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode="RGBA").save(full, format="PNG", optimize=True)
    return rel


def main() -> None:
    os.makedirs(os.path.join(REPO_ROOT, "assets_src/world"), exist_ok=True)
    os.makedirs(os.path.join(REPO_ROOT, "assets_src/sprites"), exist_ok=True)

    # 1. Crisp Song-Ming Gongbi meadow ground tile
    meadow_art = latest_artifact("terrain_gongbi_meadow")
    meadow_src_rel = "assets_src/world/terrain_gongbi_meadow_raw.jpg"
    shutil.copy2(meadow_art, os.path.join(REPO_ROOT, meadow_src_rel))

    meadow_out = make_crisp_overlap_seamless(Image.open(meadow_art), out_size=1024, overlap=80)
    moss_rel = "project/assets/world/tex_moss_earth.png"
    meadow_out.save(os.path.join(REPO_ROOT, moss_rel), format="PNG", optimize=True)

    # 2. Extract Peddler NPC + Pharmacy Counter + Discarded Pill Basket
    props_art = latest_artifact("prop_peddler_and_yaolu")
    props_src_rel = "assets_src/world/prop_peddler_and_yaolu_raw.jpg"
    shutil.copy2(props_art, os.path.join(REPO_ROOT, props_src_rel))

    # 16:9 sheet height is ~768, so shadow_y_start=680 safely avoids body pixels
    peddler_fig, counter_fig, basket_fig = isolate_sheet_components(
        props_art, expected_n=3, shadow_y_start=690, strip_enclosed_cream=True
    )

    peddler_png_rel = build_sheet(
        "npc_peddler",
        peddler_fig,
        build_back_silhouette_fallback(peddler_fig),
        target_h=158,
        cell_w=224,
        cell_h=224,
        accent_rgb=(172, 148, 102),
        is_quadruped=False,
        is_enemy=False,
    )
    peddler_json_rel = "project/assets/sprites/npc_peddler_sheet.json"

    counter_rel = "project/assets/world/prop_yaolu_counter.png"
    save_grounded_prop(counter_fig, target_h=156, out_rel=counter_rel, shadow_alpha=92)

    basket_rel = "project/assets/world/prop_discarded_pill_basket.png"
    save_grounded_prop(basket_fig, target_h=72, out_rel=basket_rel, shadow_alpha=88)

    # 3. Feather camphor tree root moss rim
    camphor_rel = feather_camphor_root_rim()

    # 4. Update docs/asset-manifest.json
    manifest_path = os.path.join(REPO_ROOT, "docs/asset-manifest.json")
    with open(manifest_path, "r", encoding="utf-8") as fh:
        manifest_doc = json.load(fh)
    by_path = {entry["path"]: entry for entry in manifest_doc.get("assets", [])}

    lic = "AI-Assisted First-Party Original Asset (Gemini Imagen + Manual/Programmatic Song-Ming Gongbi Refinement, Commercial Rights Cleared)"

    manifest_entries = [
        (
            moss_rel,
            meadow_src_rel,
            "world_terrain",
            "generate_image (terrain_gongbi_meadow: Song-Ming Gongbi hand-inked short grass tufts, moss patches & fallen bamboo leaves) + 80px edge-only overlap seamless wrap (zero interior blur)",
        ),
        (
            peddler_png_rel,
            props_src_rel,
            "sprite_sheet",
            "generate_image (prop_peddler_and_yaolu: 35-deg Song-Ming Gongbi wandering Daoist peddler in conical bamboo hat & grey hemp robe) + connected-component exterior cutout & 8x6 keyframe sheet",
        ),
        (
            counter_rel,
            props_src_rel,
            "world_prop",
            "generate_image (prop_peddler_and_yaolu: 35-deg Song-Ming Gongbi wooden apothecary counter with celadon medicine jars, dried herbs & gourd sign) + grounded contact shadow",
        ),
        (
            basket_rel,
            props_src_rel,
            "world_prop",
            "generate_image (prop_peddler_and_yaolu: 35-deg Song-Ming Gongbi woven bamboo discard basket with scorched failed pills & herb stems) + grounded contact shadow",
        ),
        (
            camphor_rel,
            by_path[camphor_rel]["source_path"],
            "world_prop",
            by_path[camphor_rel]["creation_method"] + " + root-skirt alpha feathering",
        ),
    ]

    for rel_p, src_p, cat, method in manifest_entries:
        abs_p = os.path.join(REPO_ROOT, rel_p)
        with Image.open(abs_p) as im_chk:
            dims = f"{im_chk.width}x{im_chk.height}"
        by_path[rel_p] = {
            "path": rel_p,
            "source_path": src_p,
            "category": cat,
            "dimensions": dims,
            "sha256": sha256_file(abs_p),
            "creation_method": method,
            "generated_date": "2026-11-26",
            "license": lic,
        }

    # Check if .json sprite metadata files are tracked in manifest too
    if any(p.endswith("_sheet.json") for p in by_path):
        abs_j = os.path.join(REPO_ROOT, peddler_json_rel)
        by_path[peddler_json_rel] = {
            "path": peddler_json_rel,
            "source_path": props_src_rel,
            "category": "sprite_meta",
            "dimensions": "json",
            "sha256": sha256_file(abs_j),
            "creation_method": "Generated 8x6 animation row & head_top_px metadata for npc_peddler",
            "generated_date": "2026-11-26",
            "license": lic,
        }

    manifest_doc["assets"] = sorted(by_path.values(), key=lambda x: x["path"])
    with open(manifest_path, "w", encoding="utf-8") as fh:
        json.dump(manifest_doc, fh, ensure_ascii=False, indent=2)
        fh.write("\n")

    print("Round 3 assets built cleanly! Total manifest entries:", len(manifest_doc["assets"]))


if __name__ == "__main__":
    main()
