"""Opaque-box E2E host checks for W4 (F13 world palette, F16 exports/chunks/masters/scope & T3-W4-04).

Covers:
- T1-F16-01 (baseline): Web (<85 MiB .pck+.wasm), Linux (+x ELF), and Windows (PE + PCK) build artifacts.
- T1-F16-02 (baseline): chunk_manifest.json <= 1,572,864 B (1.5 MiB) parts, .gz parity & SHA-256 reassembly.
- T1-F16-03 (baseline): 4 Gate 3 1920x1080 target masters intact & SHA-256 matched in asset-manifest.json.
- T1-F16-05 (polish_r4): docs/reviews/gate3_comparisons/ 4-scene side-by-side comparison plates.
- T2-F13-04 (baseline): 0 fluorescent RGB pixels across 100% of project/assets/world/*.png.
- T2-F16-01 (baseline): builds/web/index.pck zero assets_src/.agents/personal saves + git ls-files hygiene.
- T2-F16-02 (baseline): Large non-tile plates configure compress/mode=1 (excluding world/tex_*.png tiles).
- T2-F16-03 (baseline): docs/asset-manifest.json zero orphaned entries + zero slash-tmp literals in active code/tests.
- T2-F16-04 (baseline): builds/web/index.html zh-CN, chunk loader, sandboxed storage shield & zero external CDN scripts.
- T2-F16-05 (baseline): AGENTS.md & 40-vertical-slice-plan.md human blind-playtest honesty gate guard.
- T3-W4-04 (baseline): Cross-validate manifest_guard.py --check + data->manifest asset refs + web chunks + Ch1 scope lock.
"""

from __future__ import annotations

import gzip
import hashlib
import importlib.util
import json
import os
import re
import struct
import subprocess
import sys
from pathlib import Path
from typing import Any

from PIL import Image

from tools.e2e import CheckContext, make_check
from tools.e2e.visual_master_inspector import (
    GATE3_MASTER_FILES,
    count_fluorescent_pixels,
    load_gate3_master,
    load_rgb_or_rgba,
    load_rgba,
    sample_roi_rgb_stats,
)

MAX_WEB_BUNDLE_BYTES: int = 85 * 1024 * 1024  # 89,128,960 bytes (85 MiB)
MAX_CHUNK_PART_BYTES: int = 1536 * 1024  # 1,572,864 bytes (1.5 MiB exact ceiling)
CANONICAL_MASTERS: tuple[tuple[str, str], ...] = (
    ("a", "master_a_tingyu_town.png"),
    ("b", "master_b_cangmu_rtwp.png"),
    ("c", "master_c_temple_stage.png"),
    ("d", "master_d_dao_casket.png"),
)


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_path(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        while True:
            chunk = fh.read(131072)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def _resolve_builds_dir(ctx: CheckContext) -> Path:
    """Resolve ``builds/`` directory without cross-worktree race conditions.

    - When ``repo_root / "builds"`` exists on disk (e.g. main repository after running
      ``tools/export_builds.sh``), inspect ``repo_root / "builds"`` directly.
    - When running inside a clean ``git worktree`` where gitignored ``builds/`` does not
      exist on disk, run genuine ``godot --headless --export-release`` + ``postprocess_web_export.py``
      against ``ctx.project_dir`` into an isolated per-run scratch cache (never touching
      ``repo_root``, ``/tmp``, or another worktree's mutable ``builds/``).
    """
    local_builds = ctx.repo_root / "builds"
    if local_builds.is_dir():
        return local_builds

    run_root = ctx.scratch_dir.parent.parent
    scratch_builds = run_root / "worktree_builds"
    sentinel = scratch_builds / ".export_complete"
    if sentinel.is_file():
        return scratch_builds

    godot_bin = Path(os.environ.get("GODOT_BIN", "/home/antigravity/.local/bin/godot"))
    export_xdg_data = run_root / "export_xdg_data"
    export_xdg_cfg = run_root / "export_xdg_cfg"
    export_xdg_cache = run_root / "export_xdg_cache"
    export_tmp = run_root / "export_tmp"
    for d in (
        export_xdg_data / "godot",
        export_xdg_cfg,
        export_xdg_cache,
        export_tmp,
        scratch_builds / "web",
        scratch_builds / "linux",
        scratch_builds / "windows",
    ):
        d.mkdir(parents=True, exist_ok=True)

    host_templates = Path.home() / ".local/share/godot/export_templates"
    link_templates = export_xdg_data / "godot" / "export_templates"
    if host_templates.is_dir() and not link_templates.exists():
        link_templates.symlink_to(host_templates)

    env = dict(os.environ)
    env["XDG_DATA_HOME"] = str(export_xdg_data)
    env["XDG_CONFIG_HOME"] = str(export_xdg_cfg)
    env["XDG_CACHE_HOME"] = str(export_xdg_cache)
    env["TMPDIR"] = str(export_tmp)
    env["TEMP"] = str(export_tmp)
    env["TMP"] = str(export_tmp)
    env["PYTHONDONTWRITEBYTECODE"] = "1"

    targets = (
        ("Web", scratch_builds / "web" / "index.html"),
        ("Linux", scratch_builds / "linux" / "chenyuan-xianxia.x86_64"),
        ("Windows Desktop", scratch_builds / "windows" / "chenyuan-xianxia.exe"),
    )
    for preset, out_file in targets:
        subprocess.run(
            [
                str(godot_bin),
                "--headless",
                "--audio-driver",
                "Dummy",
                "--path",
                str(ctx.project_dir),
                "--export-release",
                preset,
                str(out_file),
            ],
            cwd=str(ctx.project_dir),
            env=env,
            capture_output=True,
            text=True,
            check=True,
            timeout=120.0,
        )

    linux_bin = scratch_builds / "linux" / "chenyuan-xianxia.x86_64"
    if linux_bin.is_file():
        linux_bin.chmod(0o755)

    post_script = ctx.repo_root / "tools" / "postprocess_web_export.py"
    spec = importlib.util.spec_from_file_location("_e2e_postprocess_web", post_script)
    if spec is not None and spec.loader is not None:
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        setattr(mod, "WEB_DIR", str(scratch_builds / "web"))
        setattr(mod, "CHUNKS_DIR", str(scratch_builds / "web" / "chunks"))
        mod.main()

    sentinel.write_text("ok\n", encoding="utf-8")
    return scratch_builds


def _parse_pck_paths(pck_path: Path) -> tuple[bool, list[str]]:
    """Parse Godot 4 PCK v2/v3 file table or extract res:// paths deterministically."""
    data = pck_path.read_bytes()
    if len(data) < 40 or data[:4] != b"GDPC":
        return False, []

    paths: list[str] = []
    try:
        fmt_ver, _ver_maj, _ver_min, _ver_patch, pack_flags = struct.unpack_from("<5I", data, 4)
        if fmt_ver >= 2:
            _file_base, dir_offset = struct.unpack_from("<QQ", data, 24)
            pos = dir_offset if (pack_flags & 2) == 0 and 0 < dir_offset < len(data) else 104
            if pos + 4 <= len(data):
                file_count = struct.unpack_from("<I", data, pos)[0]
                pos += 4
                if 0 < file_count < 100000:
                    for _ in range(file_count):
                        if pos + 4 > len(data):
                            break
                        plen = struct.unpack_from("<I", data, pos)[0]
                        pos += 4
                        if plen == 0 or plen > 4096 or pos + plen + 32 > len(data):
                            break
                        raw_p = data[pos : pos + plen].rstrip(b"\x00").decode("utf-8", errors="replace")
                        paths.append(raw_p)
                        pos += plen + 8 + 8 + 16 + 4
    except struct.error:
        paths = []

    if len(paths) < 20:
        # Regex fallback over binary table for res:// strings
        found = re.findall(rb"res://[^\x00\r\n\"'<>]{2,220}", data)
        paths = sorted({m.decode("utf-8", errors="replace") for m in found})
    return True, paths


def _check_t1_f16_01_platform_exports_and_budget(ctx: CheckContext) -> None:
    builds_dir = _resolve_builds_dir(ctx)
    web_dir = builds_dir / "web"
    linux_bin = builds_dir / "linux" / "chenyuan-xianxia.x86_64"
    win_exe = builds_dir / "windows" / "chenyuan-xianxia.exe"
    win_pck = builds_dir / "windows" / "chenyuan-xianxia.pck"

    req_web = ("index.pck", "index.wasm", "index.html", "index.js", "chunk_manifest.json")
    for fname in req_web:
        fpath = web_dir / fname
        ctx.assert_true(fpath.is_file() and fpath.stat().st_size > 0, f"Web artifact exists & non-empty: {fname}")

    ctx.assert_true(linux_bin.is_file() and linux_bin.stat().st_size > 1_000_000, "Linux x86_64 binary exists")
    if linux_bin.is_file():
        ctx.assert_true(os.access(linux_bin, os.X_OK), "Linux x86_64 binary has +x executable permission")
        with linux_bin.open("rb") as lfh:
            ctx.assert_eq(lfh.read(4), b"\x7fELF", "Linux binary starts with valid ELF magic")

    ctx.assert_true(win_exe.is_file() and win_exe.stat().st_size > 1_000_000, "Windows .exe binary exists")
    if win_exe.is_file():
        with win_exe.open("rb") as wfh:
            ctx.assert_eq(wfh.read(2), b"MZ", "Windows .exe starts with valid MZ PE header")

    ctx.assert_true(win_pck.is_file() and win_pck.stat().st_size > 1_000_000, "Windows .pck archive exists")
    if win_pck.is_file():
        with win_pck.open("rb") as pfh:
            ctx.assert_eq(pfh.read(4), b"GDPC", "Windows .pck starts with valid GDPC magic")

    pck_path = web_dir / "index.pck"
    wasm_path = web_dir / "index.wasm"
    if pck_path.is_file() and wasm_path.is_file():
        pck_sz = pck_path.stat().st_size
        wasm_sz = wasm_path.stat().st_size
        combined_sz = pck_sz + wasm_sz
        ctx.record_metric("web_pck_bytes", pck_sz)
        ctx.record_metric("web_wasm_bytes", wasm_sz)
        ctx.record_metric("web_combined_mib", round(combined_sz / (1024.0 * 1024.0), 2))
        ctx.assert_gt(combined_sz, 20 * 1024 * 1024, "Web bundle is non-trivial (>20 MiB)")
        ctx.assert_lt(
            combined_sz,
            MAX_WEB_BUNDLE_BYTES,
            "Web index.pck + index.wasm stays strictly < 85 MiB (89,128,960 B)",
        )


def _check_t1_f16_02_chunk_manifest_and_reassembly(ctx: CheckContext) -> None:
    builds_dir = _resolve_builds_dir(ctx)
    web_dir = builds_dir / "web"
    manifest_file = web_dir / "chunk_manifest.json"
    ctx.assert_true(manifest_file.is_file(), "builds/web/chunk_manifest.json exists")
    if not manifest_file.is_file():
        return

    manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
    ctx.assert_eq(
        sorted(manifest.keys()),
        ["index.pck", "index.wasm"],
        "chunk_manifest.json keys are exactly ['index.pck', 'index.wasm']",
    )

    max_seen_part = 0
    total_parts = 0
    for asset_name in ("index.wasm", "index.pck"):
        entry = manifest.get(asset_name, {})
        parts = entry.get("parts", [])
        src_path = web_dir / asset_name
        ctx.assert_true(src_path.is_file(), f"Monolithic {asset_name} exists for SHA-256 comparison")
        ctx.assert_gt(len(parts), 0, f"{asset_name} has >= 1 chunk part")
        if not src_path.is_file() or not parts:
            continue

        reassembled = bytearray()
        for idx, part in enumerate(parts):
            rel_url = str(part.get("url", ""))
            declared_sz = int(part.get("size", -1))
            part_path = web_dir / rel_url
            ctx.assert_true(part_path.is_file(), f"Chunk file exists: {rel_url}")
            if not part_path.is_file():
                continue
            raw_bytes = part_path.read_bytes()
            actual_sz = len(raw_bytes)
            max_seen_part = max(max_seen_part, actual_sz)
            total_parts += 1

            ctx.assert_gt(actual_sz, 0, f"Chunk {rel_url} is non-empty")
            ctx.assert_eq(actual_sz, declared_sz, f"Chunk {rel_url} disk size matches manifest size")
            ctx.assert_le(
                actual_sz,
                MAX_CHUNK_PART_BYTES,
                f"Chunk {rel_url} size <= 1,572,864 B (1.5 MiB)",
            )

            if asset_name == "index.wasm":
                gz_path = Path(str(part_path) + ".gz")
                ctx.assert_true(gz_path.is_file(), f"WASM pre-compressed .gz chunk exists: {gz_path.name}")
                if gz_path.is_file():
                    gz_bytes = gz_path.read_bytes()
                    ctx.assert_eq(
                        len(gz_bytes),
                        int(part.get("gz_size", -1)),
                        f"{gz_path.name} size matches manifest gz_size",
                    )
                    decompressed = gzip.decompress(gz_bytes)
                    ctx.assert_eq(
                        decompressed,
                        raw_bytes,
                        f"{gz_path.name} gunzips byte-identically to {part_path.name} (part #{idx})",
                    )

            reassembled.extend(raw_bytes)

        src_bytes = src_path.read_bytes()
        ctx.assert_eq(
            len(reassembled),
            int(entry.get("total_size", -1)),
            f"Reassembled {asset_name} length matches manifest total_size",
        )
        ctx.assert_eq(len(reassembled), len(src_bytes), f"Reassembled {asset_name} length matches monolithic file")
        ctx.assert_eq(
            _sha256_bytes(bytes(reassembled)),
            _sha256_bytes(src_bytes),
            f"Reassembled {asset_name} SHA-256 matches monolithic {asset_name} 100%",
        )

    ctx.record_metric("total_chunks", total_parts)
    ctx.record_metric("max_chunk_bytes", max_seen_part)


def _check_t1_f16_03_gate3_masters_intact(ctx: CheckContext) -> None:
    manifest_path = ctx.repo_root / "docs" / "asset-manifest.json"
    ctx.assert_true(manifest_path.is_file(), "docs/asset-manifest.json exists")
    if not manifest_path.is_file():
        return

    manifest_doc = json.loads(manifest_path.read_text(encoding="utf-8"))
    by_path = {str(item.get("path", "")): item for item in manifest_doc.get("assets", [])}

    for key, fname in CANONICAL_MASTERS:
        review_master = ctx.repo_root / "docs" / "reviews" / "gate3_masters" / fname
        ui_master_rel = f"project/assets/ui/masters/{fname}"
        ui_master = ctx.repo_root / ui_master_rel

        ctx.assert_true(review_master.is_file(), f"Gate 3 review benchmark exists: {fname}")
        ctx.assert_true(ui_master.is_file(), f"Imported UI master counterpart exists: {ui_master_rel}")
        ctx.assert_true(ui_master_rel in by_path, f"{ui_master_rel} is registered in docs/asset-manifest.json")
        if not review_master.is_file() or not ui_master.is_file():
            continue

        arr = load_gate3_master(ctx.repo_root, key)
        ctx.assert_eq(arr.shape, (1080, 1920, 3), f"{fname} has exact 1920x1080 RGB dimensions")
        stats = sample_roi_rgb_stats(arr, (0, 0, 1920, 1080))
        ctx.assert_gt(stats["std_luma"], 15.0, f"{fname} has rich non-blank luminance variance")
        ctx.assert_eq(count_fluorescent_pixels(arr), 0, f"{fname} has 0 fluorescent neon pixels")

        ui_sha = _sha256_path(ui_master)
        rev_sha = _sha256_path(review_master)
        if ui_master_rel in by_path:
            ctx.assert_eq(
                ui_sha,
                str(by_path[ui_master_rel].get("sha256", "")),
                f"{ui_master_rel} SHA-256 matches docs/asset-manifest.json",
            )
        ctx.assert_eq(ui_sha, rev_sha, f"{fname} matches byte-for-byte between gate3_masters/ and ui/masters/")
        ctx.assert_true(key in GATE3_MASTER_FILES, f"visual_master_inspector maps key '{key}'")


def _check_t1_f16_05_gate3_comparison_plates(ctx: CheckContext) -> None:
    comp_dir = ctx.repo_root / "docs" / "reviews" / "gate3_comparisons"
    ctx.assert_true(
        comp_dir.is_dir(),
        "Polish R4/M5 dossier directory docs/reviews/gate3_comparisons/ exists",
    )
    if not comp_dir.is_dir():
        return

    images = sorted(
        [p for p in comp_dir.rglob("*") if p.is_file() and p.suffix.lower() in {".png", ".webp"}]
    )
    ctx.assert_ge(len(images), 4, "docs/reviews/gate3_comparisons/ contains >= 4 comparison/capture plates")

    scene_tokens: dict[str, tuple[str, ...]] = {
        "master_a": ("master_a", "tingyu", "scene_a", "plate_a", "r4"),
        "master_b": ("master_b", "cangmu", "rtwp", "scene_b", "plate_b", "r1", "r2"),
        "master_c": ("master_c", "temple", "narrative", "portrait", "scene_c", "plate_c"),
        "master_d": ("master_d", "casket", "dao_casket", "tome", "scene_d", "plate_d", "r3"),
    }
    matched_scenes: dict[str, str] = {}

    for img_path in images:
        low_name = img_path.name.lower()
        arr = load_rgb_or_rgba(img_path)
        h, w = int(arr.shape[0]), int(arr.shape[1])
        ctx.assert_true(
            (w == 1920 and h == 1080) or (w >= 3840 and h >= 1080),
            f"Comparison plate {img_path.name} is 1920x1080 capture or >=3840x1080 side-by-side ({w}x{h})",
        )
        stats = sample_roi_rgb_stats(arr, (0, 0, w, h))
        ctx.assert_gt(stats["std_luma"], 8.0, f"Comparison plate {img_path.name} has non-blank visual variance")
        ctx.assert_eq(
            count_fluorescent_pixels(arr),
            0,
            f"Comparison plate {img_path.name} has 0 fluorescent RGB pixels",
        )
        for skey, toks in scene_tokens.items():
            if any(tok in low_name for tok in toks):
                matched_scenes[skey] = img_path.name

    for skey in ("master_a", "master_b", "master_c", "master_d"):
        ctx.assert_true(
            skey in matched_scenes,
            f"docs/reviews/gate3_comparisons/ includes verified plate for {skey}",
        )
    ctx.record_metric("comparison_plate_count", len(images))


def _check_t2_f13_04_world_assets_zero_fluorescent(ctx: CheckContext) -> None:
    world_dir = ctx.project_dir / "assets" / "world"
    ctx.assert_true(world_dir.is_dir(), "project/assets/world/ directory exists")
    pngs = sorted(world_dir.glob("*.png"))
    ctx.assert_ge(len(pngs), 20, "project/assets/world/ contains >= 20 world PNG assets")

    offenders: list[str] = []
    for png in pngs:
        rgba = load_rgba(png)
        h, w = int(rgba.shape[0]), int(rgba.shape[1])
        ctx.assert_true(w >= 32 and h >= 32, f"World asset {png.name} has valid dimensions ({w}x{h})")
        opaque_cnt = int((rgba[..., 3] > 8).sum())
        ctx.assert_gt(opaque_cnt, 64, f"World asset {png.name} has non-empty alpha content")
        vis_rgba = rgba.copy()
        vis_rgba[vis_rgba[..., 3] < 48, 3] = 0
        neon_px = count_fluorescent_pixels(vis_rgba, val_thresh=245, sat_thresh=0.92)
        if neon_px > 0:
            offenders.append(f"{png.name}({neon_px}px)")

    ctx.record_metric("world_png_count", len(pngs))
    ctx.assert_eq(
        offenders,
        [],
        "0 fluorescent neon RGB pixels (max>=245 & sat>=0.92) across all project/assets/world/*.png",
    )


def _check_t2_f16_01_pck_and_git_hygiene(ctx: CheckContext) -> None:
    builds_dir = _resolve_builds_dir(ctx)
    pck_path = builds_dir / "web" / "index.pck"
    ctx.assert_true(pck_path.is_file(), "builds/web/index.pck exists")
    if pck_path.is_file():
        ok_magic, pck_paths = _parse_pck_paths(pck_path)
        ctx.assert_true(ok_magic, "builds/web/index.pck has valid GDPC header")
        ctx.assert_ge(len(pck_paths), 50, "builds/web/index.pck packs >= 50 res:// entries")

        bad_pck = [
            p
            for p in pck_paths
            if "assets_src/" in p
            or ".agents/" in p
            or "saves/slot_" in p
            or "saves/auto_" in p
            or p.endswith("settings.cfg")
        ]
        ctx.assert_eq(bad_pck, [], "index.pck contains 0 assets_src/, .agents/, or personal save files")

        raw_bytes = pck_path.read_bytes()
        ctx.assert_false(b"res://assets_src/" in raw_bytes, "Raw index.pck binary has 0 res://assets_src/ leaks")
        ctx.assert_false(b"CHENYUAN_XIANXIA_SAVE_SLOT" in raw_bytes, "Raw index.pck has 0 personal save payloads")
        ctx.record_metric("pck_entry_count", len(pck_paths))

    proc = subprocess.run(
        ["git", "-C", str(ctx.repo_root), "ls-files"],
        capture_output=True,
        text=True,
        check=False,
        timeout=10.0,
    )
    ctx.assert_eq(proc.returncode, 0, "git ls-files succeeded")
    tracked = [ln.strip() for ln in proc.stdout.splitlines() if ln.strip()]
    forbidden_tracked = [
        p
        for p in tracked
        if p.startswith(".agents/")
        or p in {"PROJECT.md", "TEST_INFRA.md", "TEST_READY.md"}
        or p.startswith("builds/")
        or (p.startswith("saves/") and p.endswith(".json"))
        or "/saves/slot_" in p
    ]
    ctx.assert_eq(
        forbidden_tracked,
        [],
        "git ls-files tracks 0 .agents/, PROJECT.md, TEST_INFRA.md, TEST_READY.md, builds/, or save files",
    )


def _check_t2_f16_02_large_plate_import_compression(ctx: CheckContext) -> None:
    assets_dir = ctx.project_dir / "assets"
    mandatory_dirs = (
        assets_dir / "portraits",
        assets_dir / "cg",
        assets_dir / "ui" / "masters",
    )
    checked_count = 0
    bad_imports: list[str] = []

    for mdir in mandatory_dirs:
        ctx.assert_true(mdir.is_dir(), f"Asset directory exists: {mdir.relative_to(ctx.repo_root)}")
        for imp_path in sorted(mdir.glob("*.png.import")):
            checked_count += 1
            txt = imp_path.read_text(encoding="utf-8")
            if "compress/mode=1" not in txt:
                bad_imports.append(imp_path.relative_to(ctx.repo_root).as_posix())

    # Also check any large (>1024px) non-tile plates in ui/frames/ or world/ (excluding world/tex_*.png tiles)
    for extra_dir in (assets_dir / "ui" / "frames", assets_dir / "world"):
        if not extra_dir.is_dir():
            continue
        for png_path in sorted(extra_dir.glob("*.png")):
            if extra_dir.name == "world" and png_path.name.startswith("tex_"):
                # Tileable ground textures must remain compress/mode=0 for TEXTURE_REPEAT_ENABLED
                tile_imp = Path(str(png_path) + ".import")
                if tile_imp.is_file():
                    tile_txt = tile_imp.read_text(encoding="utf-8")
                    ctx.assert_str_contains(
                        tile_txt,
                        "compress/mode=0",
                        f"Tileable ground texture {png_path.name}.import preserves compress/mode=0",
                    )
                continue
            with Image.open(png_path) as im:
                w, h = im.size
            if w > 1024 or h > 1024:
                imp_path = Path(str(png_path) + ".import")
                checked_count += 1
                if not imp_path.is_file() or "compress/mode=1" not in imp_path.read_text(encoding="utf-8"):
                    bad_imports.append(png_path.relative_to(ctx.repo_root).as_posix())

    ctx.assert_ge(checked_count, 35, "Checked >= 35 large plate .import configurations")
    ctx.assert_eq(
        bad_imports,
        [],
        "100% of large non-tile plates (portraits, cg, ui/masters, >1024px frames/props) use compress/mode=1",
    )
    ctx.record_metric("checked_large_imports", checked_count)


def _check_t2_f16_03_manifest_reverse_and_no_tmp_literals(ctx: CheckContext) -> None:
    manifest_path = ctx.repo_root / "docs" / "asset-manifest.json"
    ctx.assert_true(manifest_path.is_file(), "docs/asset-manifest.json exists")
    if manifest_path.is_file():
        doc = json.loads(manifest_path.read_text(encoding="utf-8"))
        entries = doc.get("assets", [])
        ctx.assert_ge(len(entries), 140, "docs/asset-manifest.json tracks >= 140 assets")
        orphaned: list[str] = []
        missing_src: list[str] = []
        seen_paths: set[str] = set()
        duplicate_paths: list[str] = []
        for entry in entries:
            rel_p = str(entry.get("path", ""))
            src_p = str(entry.get("source_path", ""))
            if rel_p in seen_paths:
                duplicate_paths.append(rel_p)
            seen_paths.add(rel_p)
            if not rel_p or not (ctx.repo_root / rel_p).is_file():
                orphaned.append(rel_p)
            if not src_p or not (ctx.repo_root / src_p).is_file():
                missing_src.append(f"{rel_p}->{src_p}")
        ctx.assert_eq(duplicate_paths, [], "0 duplicate path entries in docs/asset-manifest.json")
        ctx.assert_eq(orphaned, [], "0 orphaned/stale entries in docs/asset-manifest.json")
        ctx.assert_eq(missing_src, [], "100% of manifest entries resolve valid assets_src/ files")

    # Construct needle without literal slash-tmp in this source file
    slash_tmp_dir = chr(47) + "tmp" + chr(47)
    slash_tmp_quote_1 = '"' + chr(47) + "tmp" + '"'
    slash_tmp_quote_2 = "'" + chr(47) + "tmp" + "'"

    scan_targets: list[Path] = []
    for rel_dir in ("project/src", "project/tests", "tools/e2e"):
        d = ctx.repo_root / rel_dir
        if d.is_dir():
            for f in sorted(d.rglob("*")):
                if f.is_file() and f.suffix.lower() in {".gd", ".py", ".sh", ".tscn", ".gdshader"}:
                    scan_targets.append(f)
    run_all = ctx.repo_root / "tools" / "run_all_checks.py"
    if run_all.is_file():
        scan_targets.append(run_all)
    for r_script in sorted((ctx.repo_root / "tools").glob("build_polish_r*.py")):
        if r_script.is_file():
            scan_targets.append(r_script)

    offenders: list[str] = []
    comment_prefixes = ("#", "//")
    guard_markers = (
        ".startswith(",
        ".begins_with(",
        "assert_false(",
        "assert_str_not_contains(",
        "fail_msg(",
    )
    for fpath in scan_targets:
        rel_s = fpath.relative_to(ctx.repo_root).as_posix()
        if rel_s == "tools/e2e/isolation_guard.py":
            # isolation_guard.py defines TMP_ROOT solely to reject /tmp paths via validate_output_path()
            continue
        for lineno, raw_line in enumerate(fpath.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            stripped = raw_line.strip()
            if not stripped or stripped.startswith(comment_prefixes):
                continue
            code_part = stripped.split("#", 1)[0] if fpath.suffix in {".py", ".gd", ".sh"} else stripped
            if any(gm in code_part for gm in guard_markers):
                continue
            if (
                slash_tmp_dir in code_part
                or slash_tmp_quote_1 in code_part
                or slash_tmp_quote_2 in code_part
            ):
                offenders.append(f"{rel_s}:{lineno}")

    ctx.record_metric("scanned_code_files", len(scan_targets))
    ctx.assert_eq(
        offenders,
        [],
        "0 '/" + "tmp/' path literals in project/src/, project/tests/, tools/e2e/, run_all_checks.py, build_polish_r*.py",
    )


def _check_t2_f16_04_web_index_html_sandbox_and_csp_safety(ctx: CheckContext) -> None:
    builds_dir = _resolve_builds_dir(ctx)
    html_path = builds_dir / "web" / "index.html"
    ctx.assert_true(html_path.is_file(), "builds/web/index.html exists")
    if not html_path.is_file():
        return

    html = html_path.read_text(encoding="utf-8")
    ctx.assert_str_contains(html, '<html lang="zh-CN">', "index.html declares lang='zh-CN'")
    ctx.assert_str_contains(html, "chunk_manifest.json", "index.html wires progressive chunk_manifest.json loader")
    ctx.assert_str_contains(html, "indexedDB", "index.html probes/shields window.indexedDB")
    ctx.assert_str_contains(html, "localStorage", "index.html shields window.localStorage for sandboxed iframes")
    ctx.assert_str_contains(html, "sessionStorage", "index.html shields window.sessionStorage for sandboxed iframes")
    ctx.assert_str_contains(
        html,
        "WebAssembly.instantiateStreaming",
        "index.html includes WebAssembly.instantiateStreaming synthetic-stream fallback",
    )
    ctx.assert_false(
        "__TOTAL_CHUNKS__" in html or "__PCK_SIZE__" in html or "__WASM_SIZE__" in html,
        "index.html template placeholders were fully substituted",
    )

    ext_scripts = re.findall(r"<script[^>]+src=[\"'](https?:)?//[^\"']+[\"']", html, flags=re.IGNORECASE)
    ext_links = re.findall(r"<link[^>]+href=[\"'](https?:)?//[^\"']+[\"']", html, flags=re.IGNORECASE)
    ctx.assert_eq(ext_scripts, [], "index.html loads 0 external third-party HTTP/CDN <script> tags")
    ctx.assert_eq(ext_links, [], "index.html loads 0 external third-party HTTP/CDN <link> stylesheets")


def _check_t2_f16_05_human_playtest_honesty_guard(ctx: CheckContext) -> None:
    agents_md = (ctx.repo_root / "AGENTS.md").read_text(encoding="utf-8")
    plan_md = (ctx.repo_root / "docs" / "design" / "40-vertical-slice-plan.md").read_text(encoding="utf-8")

    ctx.assert_str_contains(
        agents_md,
        "不把未测试或未试玩的项目标为已通过",
        "AGENTS.md enforces human-playtest honesty rule",
    )
    ctx.assert_str_contains(
        plan_md,
        "5–8 名热爱仙侠/RPG 且未参与开发的新玩家",
        "40-vertical-slice-plan.md §4 preserves external blind human playtest requirement",
    )
    ctx.assert_str_contains(
        plan_md,
        "严禁强行启动第二章（青云境）开发",
        "40-vertical-slice-plan.md §4 preserves Chapter 2 (青云境) gate lock",
    )

    reviews_dir = ctx.repo_root / "docs" / "reviews"
    fabricated_claims: list[str] = []
    forbidden_phrases = (
        "外部真人盲测已全部通过",
        "5-8名新玩家试玩已通过",
        "5–8名新玩家试玩已通过",
        "真人试玩验收：已通过",
        "blind playtest: passed",
    )
    if reviews_dir.is_dir():
        for md_file in sorted(reviews_dir.rglob("*.md")):
            content = md_file.read_text(encoding="utf-8")
            low_c = content.lower()
            for phrase in forbidden_phrases:
                if phrase.lower() in low_c:
                    fabricated_claims.append(f"{md_file.name}:{phrase}")

    ctx.assert_eq(
        fabricated_claims,
        [],
        "docs/reviews/ contains 0 fabricated external human blind-playtest completion claims",
    )


def _collect_res_asset_strings(obj: Any, out: set[str]) -> None:
    if isinstance(obj, dict):
        for v in obj.values():
            _collect_res_asset_strings(v, out)
    elif isinstance(obj, list):
        for item in obj:
            _collect_res_asset_strings(item, out)
    elif isinstance(obj, str) and obj.startswith("res://assets/"):
        out.add(obj)


def _check_t3_w4_04_cross_pipeline_manifest_chunks_and_scope(ctx: CheckContext) -> None:
    # 1. Run real tools/manifest_guard.py --check
    guard_script = ctx.repo_root / "tools" / "manifest_guard.py"
    proc = subprocess.run(
        [sys.executable, str(guard_script), "--check"],
        cwd=str(ctx.repo_root),
        capture_output=True,
        text=True,
        check=False,
        timeout=30.0,
    )
    ctx.assert_eq(proc.returncode, 0, f"manifest_guard.py --check exited 0 (stderr={proc.stderr.strip()[:200]})")
    ctx.assert_str_contains(proc.stdout, "Manifest OK:", "manifest_guard.py printed 'Manifest OK:'")

    # 2. Cross-validate 100% of res://assets/... references in project/data/**/*.json against manifest & disk
    manifest_doc = json.loads((ctx.repo_root / "docs" / "asset-manifest.json").read_text(encoding="utf-8"))
    manifest_paths = {str(e.get("path", "")) for e in manifest_doc.get("assets", [])}
    for p in manifest_paths:
        ctx.assert_true((ctx.repo_root / p).is_file(), f"Manifest reverse path exists: {p}")

    data_res_refs: set[str] = set()
    ch02_leaks: list[str] = []
    for jfile in sorted((ctx.project_dir / "data").rglob("*.json")):
        parsed = json.loads(jfile.read_text(encoding="utf-8"))
        _collect_res_asset_strings(parsed, data_res_refs)
        raw_txt = jfile.read_text(encoding="utf-8")
        for m in re.findall(r'"(ch02_[a-zA-Z0-9_]+|dlg_ch02_[a-zA-Z0-9_]+|q_main_ch02[a-zA-Z0-9_]*)"', raw_txt):
            ch02_leaks.append(f"{jfile.name}:{m}")

    ctx.assert_gt(len(data_res_refs), 15, "Extracted >= 15 res://assets/ references from project/data/*.json")
    unmanifested_refs: list[str] = []
    for res_p in sorted(data_res_refs):
        repo_rel = "project/" + res_p[len("res://") :]
        if repo_rel not in manifest_paths or not (ctx.repo_root / repo_rel).is_file():
            unmanifested_refs.append(res_p)
    ctx.assert_eq(unmanifested_refs, [], "100% of data JSON res://assets/ paths exist & are tracked in manifest")
    ctx.assert_eq(ch02_leaks, [], "0 premature Chapter 2 (ch02_*) quests/dialogues/zones in project/data/*.json")

    # 3. Cross-validate Web export <85 MiB + <=1.5 MiB chunk reassembly
    builds_dir = _resolve_builds_dir(ctx)
    web_dir = builds_dir / "web"
    pck_b = (web_dir / "index.pck").read_bytes()
    wasm_b = (web_dir / "index.wasm").read_bytes()
    ctx.assert_lt(len(pck_b) + len(wasm_b), MAX_WEB_BUNDLE_BYTES, "Web .pck+.wasm < 85 MiB")
    cman = json.loads((web_dir / "chunk_manifest.json").read_text(encoding="utf-8"))
    for name, src_b in (("index.pck", pck_b), ("index.wasm", wasm_b)):
        parts = cman[name]["parts"]
        joined = b"".join((web_dir / p["url"]).read_bytes() for p in parts)
        ctx.assert_true(all(0 < int(p["size"]) <= MAX_CHUNK_PART_BYTES for p in parts), f"{name} chunks <= 1.5 MiB")
        ctx.assert_eq(_sha256_bytes(joined), _sha256_bytes(src_b), f"{name} chunk reassembly SHA-256 parity")


def get_checks() -> list[dict[str, Any]]:
    return [
        make_check(
            "T1-F16-01",
            1,
            "F16",
            "baseline",
            "Web (<85 MiB .pck+.wasm), Linux (+x ELF), and Windows (PE + PCK) export artifacts intact",
            _check_t1_f16_01_platform_exports_and_budget,
        ),
        make_check(
            "T1-F16-02",
            1,
            "F16",
            "baseline",
            "chunk_manifest.json parts <= 1,572,864 B (1.5 MiB), .gz gunzip parity & SHA-256 reassembly",
            _check_t1_f16_02_chunk_manifest_and_reassembly,
        ),
        make_check(
            "T1-F16-03",
            1,
            "F16",
            "baseline",
            "4 Gate 3 1920x1080 visual masters intact with 0 fluorescent pixels & manifest SHA-256 parity",
            _check_t1_f16_03_gate3_masters_intact,
        ),
        make_check(
            "T1-F16-05",
            1,
            "F16",
            "polish_r4",
            "docs/reviews/gate3_comparisons/ side-by-side 1920x1080 verification plates across all 4 scenes",
            _check_t1_f16_05_gate3_comparison_plates,
        ),
        make_check(
            "T2-F13-04",
            2,
            "F13",
            "baseline",
            "0 fluorescent neon RGB pixels across 100% of project/assets/world/*.png",
            _check_t2_f13_04_world_assets_zero_fluorescent,
        ),
        make_check(
            "T2-F16-01",
            2,
            "F16",
            "baseline",
            "builds/web/index.pck excludes assets_src/.agents/saves and git ls-files hygiene holds",
            _check_t2_f16_01_pck_and_git_hygiene,
        ),
        make_check(
            "T2-F16-02",
            2,
            "F16",
            "baseline",
            "100% of large non-tile plates configure compress/mode=1 while world/tex_*.png keep compress/mode=0",
            _check_t2_f16_02_large_plate_import_compression,
        ),
        make_check(
            "T2-F16-03",
            2,
            "F16",
            "baseline",
            "docs/asset-manifest.json has 0 orphaned entries and active code/tests have 0 slash-tmp literals",
            _check_t2_f16_03_manifest_reverse_and_no_tmp_literals,
        ),
        make_check(
            "T2-F16-04",
            2,
            "F16",
            "baseline",
            "builds/web/index.html enforces zh-CN, chunk loader, sandboxed storage shields & 0 external CDN scripts",
            _check_t2_f16_04_web_index_html_sandbox_and_csp_safety,
        ),
        make_check(
            "T2-F16-05",
            2,
            "F16",
            "baseline",
            "AGENTS.md & 40-vertical-slice-plan.md human blind-playtest honesty & Ch2 gate guard",
            _check_t2_f16_05_human_playtest_honesty_guard,
        ),
        make_check(
            "T3-W4-04",
            3,
            "F16",
            "baseline",
            "Cross-validate manifest_guard.py --check, JSON asset refs, <85 MiB web chunks & ch01_qinglan scope lock",
            _check_t3_w4_04_cross_pipeline_manifest_chunks_and_scope,
        ),
    ]
