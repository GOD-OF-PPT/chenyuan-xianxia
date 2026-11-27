"""Reusable pixel, palette, WCAG contrast, sprite-sheet & portrait forensics helpers.

Used by ``tools/e2e/checks_w{1..4}_*.py`` for deterministic image inspection
against Song-Ming Gongbi art bible rules and Gate 3 ``1920x1080`` target masters.
Never writes temporary files to ``/tmp``; all operations execute in memory via
``PIL.Image``, ``numpy``, and ``cv2``.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from PIL import Image

GATE3_MASTER_FILES: dict[str, str] = {
    "a": "master_a_tingyu_town.png",
    "master_a": "master_a_tingyu_town.png",
    "b": "master_b_cangmu_rtwp.png",
    "master_b": "master_b_cangmu_rtwp.png",
    "c": "master_c_temple_stage.png",
    "master_c": "master_c_temple_stage.png",
    "d": "master_d_dao_casket.png",
    "master_d": "master_d_dao_casket.png",
}


def load_rgb_or_rgba(path: Path | str) -> np.ndarray:
    """Load an image from disk into a ``uint8`` numpy array ``(H, W, 3)`` or ``(H, W, 4)``."""
    p = Path(path)
    with Image.open(p) as im:
        has_alpha = im.mode in ("RGBA", "LA", "PA") or ("transparency" in im.info)
        converted = im.convert("RGBA" if has_alpha else "RGB")
        return np.asarray(converted, dtype=np.uint8).copy()


def load_rgba(path: Path | str) -> np.ndarray:
    """Load an image from disk as ``uint8`` ``(H, W, 4)`` RGBA."""
    p = Path(path)
    with Image.open(p) as im:
        return np.asarray(im.convert("RGBA"), dtype=np.uint8).copy()


def load_gate3_master(repo_root: Path, plate_key: str) -> np.ndarray:
    """Load one of the 4 authoritative ``1920x1080`` Gate 3 master plates as RGB."""
    key = plate_key.strip().lower()
    fname = GATE3_MASTER_FILES.get(key, plate_key)
    master_path = repo_root / "docs" / "reviews" / "gate3_masters" / fname
    return load_rgb_or_rgba(master_path)[..., :3]


def count_fluorescent_pixels(
    img_rgb: np.ndarray,
    val_thresh: int = 245,
    sat_thresh: float = 0.92,
) -> int:
    """Count visible neon/fluorescent pixels violating the Song-Ming mineral palette.

    Evaluates HSV ``Value >= val_thresh`` (on ``0..255`` scale) AND
    ``Saturation >= sat_thresh`` (on ``0.0..1.0`` scale). If ``img_rgb`` has an
    alpha channel ``(H, W, 4)``, fully transparent pixels (``alpha == 0``) are
    excluded so unrendered background regions do not skew counts.
    """
    arr = np.asarray(img_rgb)
    if arr.ndim != 3 or arr.shape[2] not in (3, 4):
        raise ValueError(f"Expected (H, W, 3|4) image array, got shape {arr.shape}")

    rgb = arr[..., :3].astype(np.float32)
    cmax = rgb.max(axis=-1)
    cmin = rgb.min(axis=-1)
    sat = np.where(cmax > 0.0, (cmax - cmin) / np.maximum(cmax, 1.0), 0.0)
    mask = (cmax >= float(val_thresh)) & (sat >= float(sat_thresh))
    if arr.shape[2] == 4:
        mask &= arr[..., 3] > 0
    return int(np.count_nonzero(mask))


def _relative_luminance_srgb(rgb_norm: tuple[float, float, float]) -> float:
    lin: list[float] = []
    for ch in rgb_norm:
        c = max(0.0, min(1.0, float(ch)))
        if c <= 0.04045:
            lin.append(c / 12.92)
        else:
            lin.append(((c + 0.055) / 1.055) ** 2.4)
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def wcag_contrast_ratio(
    rgb_a: tuple[float, float, float],
    rgb_b: tuple[float, float, float],
) -> float:
    """Compute WCAG 2.1 contrast ratio ``[1.0, 21.0]`` between two RGB colors.

    Accepts either ``0..255`` RGB tuples (e.g. ``(216, 206, 190)``) or normalized
    ``0.0..1.0`` float tuples (auto-detected when all components are ``<= 1.0`` and
    at least one tuple contains a ``float``).
    """
    comps = (*rgb_a[:3], *rgb_b[:3])
    max_val = max(float(v) for v in comps)
    has_float = any(isinstance(v, (float, np.floating)) for v in comps)
    scale = 1.0 if (max_val <= 1.0 and has_float) else 255.0

    norm_a = (float(rgb_a[0]) / scale, float(rgb_a[1]) / scale, float(rgb_a[2]) / scale)
    norm_b = (float(rgb_b[0]) / scale, float(rgb_b[1]) / scale, float(rgb_b[2]) / scale)
    lum_a = _relative_luminance_srgb(norm_a)
    lum_b = _relative_luminance_srgb(norm_b)
    lighter = max(lum_a, lum_b)
    darker = min(lum_a, lum_b)
    return float((lighter + 0.05) / (darker + 0.05))


def _shift_mask_zero_pad(mask: np.ndarray, dx: int, dy: int) -> np.ndarray:
    """Translate a 2D boolean mask by ``(dx, dy)`` with zero padding (no wraparound)."""
    h, w = mask.shape
    out = np.zeros_like(mask, dtype=bool)
    src_x0 = max(0, -dx)
    src_x1 = min(w, w - dx)
    dst_x0 = max(0, dx)
    dst_x1 = min(w, w + dx)

    src_y0 = max(0, -dy)
    src_y1 = min(h, h - dy)
    dst_y0 = max(0, dy)
    dst_y1 = min(h, h + dy)

    if src_x1 > src_x0 and src_y1 > src_y0:
        out[dst_y0:dst_y1, dst_x0:dst_x1] = mask[src_y0:src_y1, src_x0:src_x1]
    return out


def centroid_aligned_iou(mask_a: np.ndarray, mask_b: np.ndarray) -> float:
    """Compute IoU between two binary alpha masks after aligning their centroids."""
    a = np.asarray(mask_a, dtype=bool)
    b = np.asarray(mask_b, dtype=bool)
    if not a.any() and not b.any():
        return 1.0
    if not a.any() or not b.any():
        return 0.0

    ya, xa = np.nonzero(a)
    yb, xb = np.nonzero(b)
    dx = int(round(float(xa.mean()) - float(xb.mean())))
    dy = int(round(float(ya.mean()) - float(yb.mean())))
    b_aligned = _shift_mask_zero_pad(b, dx, dy)
    inter = int(np.logical_and(a, b_aligned).sum())
    union = int(np.logical_or(a, b_aligned).sum())
    return float(inter / union) if union > 0 else 0.0


def _count_cell_border_opaque(mask: np.ndarray) -> int:
    """Count unique opaque pixels along the 1px outer perimeter of a sprite cell."""
    h, w = mask.shape
    if h == 0 or w == 0:
        return 0
    if h == 1 or w == 1:
        return int(np.count_nonzero(mask))
    top = int(np.count_nonzero(mask[0, :]))
    bottom = int(np.count_nonzero(mask[-1, :]))
    left = int(np.count_nonzero(mask[1:-1, 0]))
    right = int(np.count_nonzero(mask[1:-1, -1]))
    return top + bottom + left + right


def analyze_sprite_sheet_cells(
    png_path: Path,
    json_path: Path,
    alpha_thresh: int = 16,
) -> dict[str, Any]:
    """Analyze per-row/per-frame silhouettes, centroid-aligned IoU & 1px border leaks.

    Returns a dictionary containing:
    - ``actor_id``, ``image_size``, ``cell_w``, ``cell_h``, ``foot_y``, ``head_top_px``, ``cols``
    - ``rows[anim_name]``:
        - ``row``, ``start_col``, ``frame_count``
        - ``frames``: list of per-frame dicts with ``bbox`` ``(w, h, min_x, max_x, min_y, max_y)``,
          ``w``, ``h``, ``min_x``, ``max_x``, ``min_y``, ``max_y``, ``cx``, ``cy``,
          ``opaque_px``, and ``border_opaque_px``
        - ``frame0_bbox``: ``(w, h, min_x, max_x, min_y, max_y)`` of frame 0
        - ``max_w``, ``min_w``, ``max_h``, ``min_h``
        - ``intra_row_min_iou``: minimum centroid-aligned IoU across frames in this row
        - ``border_opaque_px_total``, ``border_opaque_px_max``
    - ``pairwise_row_iou["<anim_a>:<anim_b>"]``: minimum centroid-aligned IoU between
      ``anim_a`` frame 0 and any frame of ``anim_b``
    - ``pairwise_frame0_iou["<anim_a>:<anim_b>"]``: centroid-aligned IoU between
      ``anim_a`` frame 0 and ``anim_b`` frame 0
    - ``total_border_opaque_px``: sum of 1px cell-border opaque pixels across all defined frames
    """
    rgba = load_rgba(png_path)
    img_h, img_w = int(rgba.shape[0]), int(rgba.shape[1])
    meta = json.loads(Path(json_path).read_text(encoding="utf-8"))

    cell_w = int(meta.get("cell_w", 224))
    cell_h = int(meta.get("cell_h", 224))
    foot_y = int(meta.get("foot_y", max(0, cell_h - 22)))
    head_top_px = int(meta.get("head_top_px", max(40, foot_y - 44)))
    cols = int(meta.get("cols", max(1, img_w // max(1, cell_w))))
    rows_def: dict[str, Any] = dict(meta.get("rows", {}))

    rows_out: dict[str, dict[str, Any]] = {}
    row_masks: dict[str, list[np.ndarray]] = {}
    total_border_opaque = 0

    for anim_name, rdef in rows_def.items():
        row_idx = int(rdef.get("row", 0))
        start_col = int(rdef.get("start_col", 0))
        frame_count = int(rdef.get("frames", 1))
        frames_info: list[dict[str, Any]] = []
        masks: list[np.ndarray] = []

        for f_idx in range(frame_count):
            col_idx = start_col + f_idx
            x0 = col_idx * cell_w
            x1 = min(img_w, x0 + cell_w)
            y0 = row_idx * cell_h
            y1 = min(img_h, y0 + cell_h)

            cell_mask = np.zeros((cell_h, cell_w), dtype=bool)
            if x0 < img_w and y0 < img_h and x1 > x0 and y1 > y0:
                sub_alpha = rgba[y0:y1, x0:x1, 3]
                cell_mask[: y1 - y0, : x1 - x0] = sub_alpha >= int(alpha_thresh)

            masks.append(cell_mask)
            border_px = _count_cell_border_opaque(cell_mask)
            total_border_opaque += border_px

            if cell_mask.any():
                ys, xs = np.nonzero(cell_mask)
                min_x, max_x = int(xs.min()), int(xs.max())
                min_y, max_y = int(ys.min()), int(ys.max())
                w = max_x - min_x + 1
                h = max_y - min_y + 1
                cx = float(xs.mean())
                cy = float(ys.mean())
                opaque_px = int(cell_mask.sum())
            else:
                w = h = min_x = max_x = min_y = max_y = opaque_px = 0
                cx = cy = 0.0

            bbox_tuple = (w, h, min_x, max_x, min_y, max_y)
            frames_info.append(
                {
                    "frame_index": f_idx,
                    "col": col_idx,
                    "bbox": bbox_tuple,
                    "w": w,
                    "h": h,
                    "min_x": min_x,
                    "max_x": max_x,
                    "min_y": min_y,
                    "max_y": max_y,
                    "cx": cx,
                    "cy": cy,
                    "opaque_px": opaque_px,
                    "border_opaque_px": border_px,
                }
            )

        row_masks[anim_name] = masks
        intra_min_iou = 1.0
        if len(masks) >= 2:
            pair_ious: list[float] = []
            for i in range(len(masks)):
                for j in range(i + 1, len(masks)):
                    pair_ious.append(centroid_aligned_iou(masks[i], masks[j]))
            intra_min_iou = float(min(pair_ious)) if pair_ious else 1.0

        widths = [f["w"] for f in frames_info] or [0]
        heights = [f["h"] for f in frames_info] or [0]
        borders = [f["border_opaque_px"] for f in frames_info] or [0]
        f0_bbox = frames_info[0]["bbox"] if frames_info else (0, 0, 0, 0, 0, 0)

        rows_out[anim_name] = {
            "row": row_idx,
            "start_col": start_col,
            "frame_count": frame_count,
            "frames": frames_info,
            "frame0_bbox": f0_bbox,
            "bbox": f0_bbox,
            "max_w": int(max(widths)),
            "min_w": int(min(widths)),
            "max_h": int(max(heights)),
            "min_h": int(min(heights)),
            "intra_row_min_iou": intra_min_iou,
            "border_opaque_px_total": int(sum(borders)),
            "border_opaque_px_max": int(max(borders)),
        }

    pairwise_row_iou: dict[str, float] = {}
    pairwise_frame0_iou: dict[str, float] = {}
    anim_names = list(row_masks.keys())
    for a_name in anim_names:
        masks_a = row_masks[a_name]
        if not masks_a:
            continue
        f0_a = masks_a[0]
        for b_name in anim_names:
            masks_b = row_masks[b_name]
            if not masks_b:
                continue
            key = f"{a_name}:{b_name}"
            pairwise_frame0_iou[key] = centroid_aligned_iou(f0_a, masks_b[0])
            pairwise_row_iou[key] = float(
                min(centroid_aligned_iou(f0_a, mb) for mb in masks_b)
            )

    return {
        "actor_id": str(meta.get("actor_id", png_path.stem.replace("_sheet", ""))),
        "image_size": (img_w, img_h),
        "cell_w": cell_w,
        "cell_h": cell_h,
        "foot_y": foot_y,
        "head_top_px": head_top_px,
        "cols": cols,
        "rows": rows_out,
        "pairwise_row_iou": pairwise_row_iou,
        "pairwise_frame0_iou": pairwise_frame0_iou,
        "total_border_opaque_px": int(total_border_opaque),
    }


def compute_portrait_face_residual(
    calm_png: Path,
    variant_png: Path,
    robe_roi: tuple[int, int, int, int] = (250, 700, 770, 1150),
    face_roi: tuple[int, int, int, int] = (300, 120, 720, 480),
) -> dict[str, Any]:
    """Distinguish genuine facial expression art from global brightness/tint recolors.

    Fits a per-channel linear model ``variant_c ~= gain_c * calm_c + offset_c`` via
    least squares on ``robe_roi`` ``(x1, y1, x2, y2)``, then evaluates residual error
    on ``face_roi`` ``(x1, y1, x2, y2)``. If ``variant_png`` was produced merely by
    tinting/dimming ``calm_png``, ``mean_residual`` and ``p99_residual`` on
    ``face_roi`` collapse near ``0.0``; genuine redrawn brows/eyes/mouth/battle-scuffs
    produce substantial non-linear structural residuals on ``face_roi``.
    """
    calm_rgba = load_rgba(calm_png)
    var_rgba = load_rgba(variant_png)
    if calm_rgba.shape != var_rgba.shape:
        var_rgba = cv2.resize(
            var_rgba,
            (calm_rgba.shape[1], calm_rgba.shape[0]),
            interpolation=cv2.INTER_AREA,
        )

    h, w = int(calm_rgba.shape[0]), int(calm_rgba.shape[1])
    rx1, ry1, rx2, ry2 = (
        max(0, min(w, int(robe_roi[0]))),
        max(0, min(h, int(robe_roi[1]))),
        max(0, min(w, int(robe_roi[2]))),
        max(0, min(h, int(robe_roi[3]))),
    )
    fx1, fy1, fx2, fy2 = (
        max(0, min(w, int(face_roi[0]))),
        max(0, min(h, int(face_roi[1]))),
        max(0, min(w, int(face_roi[2]))),
        max(0, min(h, int(face_roi[3]))),
    )

    calm_robe = calm_rgba[ry1:ry2, rx1:rx2]
    var_robe = var_rgba[ry1:ry2, rx1:rx2]
    robe_opaque = (calm_robe[..., 3] >= 32) & (var_robe[..., 3] >= 32)
    if int(np.count_nonzero(robe_opaque)) >= 32:
        calm_robe_pts = calm_robe[robe_opaque, :3].astype(np.float64)
        var_robe_pts = var_robe[robe_opaque, :3].astype(np.float64)
    else:
        calm_robe_pts = calm_robe[..., :3].reshape(-1, 3).astype(np.float64)
        var_robe_pts = var_robe[..., :3].reshape(-1, 3).astype(np.float64)

    gains = np.ones(3, dtype=np.float64)
    offsets = np.zeros(3, dtype=np.float64)
    for c in range(3):
        design = np.column_stack([calm_robe_pts[:, c], np.ones(len(calm_robe_pts), dtype=np.float64)])
        sol, _, _, _ = np.linalg.lstsq(design, var_robe_pts[:, c], rcond=None)
        gains[c] = float(sol[0])
        offsets[c] = float(sol[1])

    robe_pred = np.clip(calm_robe_pts * gains + offsets, 0.0, 255.0)
    robe_mean_res = float(np.abs(var_robe_pts - robe_pred).mean())

    calm_face = calm_rgba[fy1:fy2, fx1:fx2]
    var_face = var_rgba[fy1:fy2, fx1:fx2]
    face_opaque = (calm_face[..., 3] >= 32) | (var_face[..., 3] >= 32)
    if int(np.count_nonzero(face_opaque)) >= 32:
        calm_face_pts = calm_face[face_opaque, :3].astype(np.float64)
        var_face_pts = var_face[face_opaque, :3].astype(np.float64)
    else:
        calm_face_pts = calm_face[..., :3].reshape(-1, 3).astype(np.float64)
        var_face_pts = var_face[..., :3].reshape(-1, 3).astype(np.float64)

    face_pred = np.clip(calm_face_pts * gains + offsets, 0.0, 255.0)
    abs_res = np.abs(var_face_pts - face_pred)
    raw_diff = np.abs(var_face_pts - calm_face_pts)

    return {
        "mean_residual": float(abs_res.mean()),
        "p99_residual": float(np.percentile(abs_res, 99.0)),
        "max_residual": float(abs_res.max()),
        "raw_max_diff": float(raw_diff.max()),
        "raw_mean_diff": float(raw_diff.mean()),
        "robe_mean_residual": robe_mean_res,
        "gains": [float(g) for g in gains],
        "offsets": [float(o) for o in offsets],
        "robe_roi": (rx1, ry1, rx2, ry2),
        "face_roi": (fx1, fy1, fx2, fy2),
    }


def sample_roi_rgb_stats(
    img: np.ndarray,
    roi: tuple[int, int, int, int],
) -> dict[str, float]:
    """Compute mean RGB/luma/saturation stats over ``(x1, y1, x2, y2)`` in ``0..255`` scale."""
    arr = np.asarray(img)
    h, w = int(arr.shape[0]), int(arr.shape[1])
    x1 = max(0, min(w, int(roi[0])))
    y1 = max(0, min(h, int(roi[1])))
    x2 = max(0, min(w, int(roi[2])))
    y2 = max(0, min(h, int(roi[3])))
    patch = arr[y1:y2, x1:x2, :3].astype(np.float64)
    if patch.size == 0:
        return {
            "mean_r": 0.0,
            "mean_g": 0.0,
            "mean_b": 0.0,
            "mean_luma": 0.0,
            "max_luma": 0.0,
            "std_luma": 0.0,
        }
    luma = 0.2126 * patch[..., 0] + 0.7152 * patch[..., 1] + 0.0722 * patch[..., 2]
    return {
        "mean_r": float(patch[..., 0].mean()),
        "mean_g": float(patch[..., 1].mean()),
        "mean_b": float(patch[..., 2].mean()),
        "mean_luma": float(luma.mean()),
        "max_luma": float(luma.max()),
        "std_luma": float(luma.std()),
    }
