#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$(command -v godot || echo "$HOME/.local/bin/godot")}"

if [[ ! -x "$GODOT_BIN" ]]; then
  echo "Error: Godot 4.3 binary not found at $GODOT_BIN" >&2
  exit 1
fi

echo "==> [1/4] Verifying asset provenance & SHA-256 manifest..."
python3 "$ROOT_DIR/tools/manifest_guard.py" --check

echo "==> [2/4] Exporting Web WASM build (builds/web/index.html)..."
rm -rf "$ROOT_DIR/builds/web"
mkdir -p "$ROOT_DIR/builds/web"
"$GODOT_BIN" --headless --path "$ROOT_DIR/project" --export-release "Web" "$ROOT_DIR/builds/web/index.html"

echo "==> [3/4] Exporting Linux x86_64 standalone build (builds/linux/chenyuan-xianxia.x86_64)..."
rm -rf "$ROOT_DIR/builds/linux"
mkdir -p "$ROOT_DIR/builds/linux"
"$GODOT_BIN" --headless --path "$ROOT_DIR/project" --export-release "Linux" "$ROOT_DIR/builds/linux/chenyuan-xianxia.x86_64"
chmod +x "$ROOT_DIR/builds/linux/chenyuan-xianxia.x86_64"

echo "==> [4/4] Exporting Windows Desktop x86_64 build (builds/windows/chenyuan-xianxia.exe)..."
rm -rf "$ROOT_DIR/builds/windows"
mkdir -p "$ROOT_DIR/builds/windows"
"$GODOT_BIN" --headless --path "$ROOT_DIR/project" --export-release "Windows Desktop" "$ROOT_DIR/builds/windows/chenyuan-xianxia.exe"

echo "==> Export complete! Artifact summary:"
du -sh "$ROOT_DIR/builds/web" "$ROOT_DIR/builds/linux" "$ROOT_DIR/builds/windows"
