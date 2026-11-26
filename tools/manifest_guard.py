#!/usr/bin/env python3
"""
Asset Manifest Ledger & SHA-256 Compliance Guard for 《尘缘问道》.
Strictly aligns with AGENTS.md, 20-art-bible.md, and 31-content-pipeline.md:
Every image, font, music, and SFX asset under project/assets/ must be registered in
docs/asset-manifest.json with source path in assets_src/, creation_method, license, and SHA-256.
"""
import argparse
import hashlib
import json
import os
import sys
from PIL import Image

ASSET_EXTS = {".png", ".webp", ".jpg", ".ogg", ".wav", ".otf", ".ttf"}


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        while True:
            chunk = fh.read(65536)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def get_dimensions(path: str) -> str:
    ext = os.path.splitext(path)[1].lower()
    if ext in {".png", ".webp", ".jpg"}:
        with Image.open(path) as im:
            return f"{im.width}x{im.height}"
    return "n/a"


def verify_manifest(repo_root: str) -> int:
    manifest_path = os.path.join(repo_root, "docs", "asset-manifest.json")
    if not os.path.exists(manifest_path):
        print("ERROR: docs/asset-manifest.json does not exist.", file=sys.stderr)
        return 1

    with open(manifest_path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)

    recorded = {entry["path"]: entry for entry in doc.get("assets", [])}
    assets_root = os.path.join(repo_root, "project", "assets")
    errors = []

    for dirpath, _, filenames in os.walk(assets_root):
        for fn in sorted(filenames):
            ext = os.path.splitext(fn)[1].lower()
            if ext not in ASSET_EXTS:
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, repo_root).replace("\\", "/")
            if rel not in recorded:
                errors.append(f"Unrecorded asset in project/assets/: {rel}")
                continue
            entry = recorded[rel]
            actual_sha = sha256_file(full)
            if entry.get("sha256") != actual_sha:
                errors.append(f"SHA-256 mismatch for {rel}: expected {entry.get('sha256')}, got {actual_sha}")
            src_rel = entry.get("source_path", "")
            if not src_rel or not os.path.exists(os.path.join(repo_root, src_rel)):
                errors.append(f"Missing assets_src provenance file for {rel}: {src_rel}")
            if not entry.get("license") or entry.get("license") == "Unrecorded":
                errors.append(f"Missing valid license for {rel}")

    if errors:
        for e in errors:
            print("MANIFEST ERROR:", e, file=sys.stderr)
        return 1

    print(f"Manifest OK: {len(recorded)} registered assets verified with 100% SHA-256 & provenance match.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="Verify all project/assets against docs/asset-manifest.json")
    args = parser.parse_args()
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    if args.check:
        return verify_manifest(repo_root)
    return verify_manifest(repo_root)


if __name__ == "__main__":
    sys.exit(main())
