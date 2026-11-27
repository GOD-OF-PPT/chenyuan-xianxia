"""Dual-Lock Formal Save & Scratch Isolation Guard for 《尘缘问道》 E2E runs.

Guarantees:
1. Zero temporary files ever touch ``/tmp`` — all per-run scratch, XDG dirs,
   Xvfb ``Xauthority`` cookies, reports, and captures live inside
   ``/home/antigravity/.gemini/jetski/scratch/e2e_run_<pid>_<id>/``.
2. Formal player saves & settings under
   ``~/.local/share/godot/app_userdata/尘缘问道/{saves,settings.cfg}`` are
   snapshotted read-only (size, ``st_mtime_ns``, SHA-256) before execution and
   verified byte-for-byte & nanosecond-for-nanosecond invariant after execution.
3. Temporary scratch directories are deterministically removed on exit (after
   copying debug artifacts when ``--keep-artifacts`` is requested).
"""

from __future__ import annotations

import atexit
import hashlib
import os
import shutil
import uuid
from pathlib import Path
from typing import Any

SCRATCH_BASE_DIR: Path = Path("/home/antigravity/.gemini/jetski/scratch")
TMP_ROOT: Path = Path("/tmp")
FORMAL_APP_DIR: Path = Path.home() / ".local/share/godot/app_userdata/尘缘问道"
FORMAL_SAVES_DIR: Path = FORMAL_APP_DIR / "saves"
FORMAL_SETTINGS_FILE: Path = FORMAL_APP_DIR / "settings.cfg"


class IsolationConfigError(RuntimeError):
    """Raised when a user CLI argument violates isolation rules (e.g. /tmp path)."""


def _is_under(path: Path, root: Path) -> bool:
    resolved_p = path.resolve(strict=False)
    resolved_r = root.resolve(strict=False)
    return resolved_p == resolved_r or resolved_r in resolved_p.parents


def validate_output_path(
    raw_path: str,
    repo_root: Path,
    *,
    forbid_repo_tracked: bool = False,
    label: str = "output path",
) -> Path:
    """Validate an output path (e.g. ``--json-out`` or ``--keep-artifacts``).

    Rejects any path under ``/tmp`` or ``FORMAL_APP_DIR``, and optionally rejects
    any path inside the git repository/worktree.
    """
    if not raw_path or not raw_path.strip():
        raise IsolationConfigError(f"Empty {label} is not allowed")
    candidate = Path(raw_path).expanduser().resolve(strict=False)
    if _is_under(candidate, TMP_ROOT):
        raise IsolationConfigError(
            f"{label} '{raw_path}' resolves inside /tmp ({candidate}), which is strictly forbidden. "
            f"Use {SCRATCH_BASE_DIR}/... instead."
        )
    if _is_under(candidate, FORMAL_APP_DIR):
        raise IsolationConfigError(
            f"{label} '{raw_path}' points inside formal player userdata ({FORMAL_APP_DIR}), forbidden!"
        )
    if forbid_repo_tracked and _is_under(candidate, repo_root):
        raise IsolationConfigError(
            f"{label} '{raw_path}' points inside repository tree ({repo_root}), forbidden!"
        )
    return candidate


def snapshot_formal_saves(
    formal_app_dir: Path = FORMAL_APP_DIR,
) -> dict[str, dict[str, Any]]:
    """Read-only snapshot of formal ``saves/`` and ``settings.cfg``.

    Never creates directories or opens files in write/append mode.
    """
    saves_dir = formal_app_dir / "saves"
    settings_file = formal_app_dir / "settings.cfg"
    snap: dict[str, dict[str, Any]] = {
        "__meta__": {
            "app_dir_exists": formal_app_dir.exists(),
            "saves_dir_exists": saves_dir.exists(),
        }
    }

    if settings_file.is_file():
        st = os.stat(settings_file, follow_symlinks=False)
        digest = hashlib.sha256(settings_file.read_bytes()).hexdigest()
        snap["settings.cfg"] = {
            "size": int(st.st_size),
            "mtime_ns": int(st.st_mtime_ns),
            "sha256": digest,
        }

    if saves_dir.exists() and saves_dir.is_dir():
        for entry in sorted(saves_dir.rglob("*")):
            if entry.is_file():
                rel_key = f"saves/{entry.relative_to(saves_dir).as_posix()}"
                st = os.stat(entry, follow_symlinks=False)
                digest = hashlib.sha256(entry.read_bytes()).hexdigest()
                snap[rel_key] = {
                    "size": int(st.st_size),
                    "mtime_ns": int(st.st_mtime_ns),
                    "sha256": digest,
                }
    return snap


def diff_formal_snapshots(
    before: dict[str, dict[str, Any]],
    after: dict[str, dict[str, Any]],
) -> list[str]:
    """Return human-readable difference lines if formal saves/settings changed."""
    diffs: list[str] = []
    all_keys = sorted(set(before.keys()) | set(after.keys()))
    for key in all_keys:
        if key not in before:
            diffs.append(f"Unexpected file created in formal userdata: {key}")
        elif key not in after:
            diffs.append(f"Formal userdata file deleted: {key}")
        elif before[key] != after[key]:
            diffs.append(
                f"Formal userdata modified at '{key}': before={before[key]} vs after={after[key]}"
            )
    return diffs


class IsolationGuard:
    """Context manager managing isolated scratch XDG/TMP dirs and formal-save checks."""

    def __init__(self, scratch_base: Path = SCRATCH_BASE_DIR) -> None:
        if _is_under(scratch_base, TMP_ROOT):
            raise IsolationConfigError(f"Scratch base must never be inside /tmp: {scratch_base}")
        self.scratch_base: Path = scratch_base
        self.run_id: str = f"e2e_run_{os.getpid()}_{uuid.uuid4().hex[:8]}"
        self.run_dir: Path = self.scratch_base / self.run_id
        self.xdg_data_dir: Path = self.run_dir / "xdg_data"
        self.xdg_config_dir: Path = self.run_dir / "xdg_config"
        self.xdg_cache_dir: Path = self.run_dir / "xdg_cache"
        self.tmp_dir: Path = self.run_dir / "tmp"
        self.reports_dir: Path = self.run_dir / "reports"
        self.shots_dir: Path = self.run_dir / "shots"
        self.py_scratch_dir: Path = self.run_dir / "py_scratch"
        self.xauthority_file: Path = self.tmp_dir / "Xauthority"

        self.pre_snapshot: dict[str, dict[str, Any]] = {}
        self.post_snapshot: dict[str, dict[str, Any]] = {}
        self.cleaned_up: bool = False
        self._entered: bool = False

    def __enter__(self) -> "IsolationGuard":
        self.pre_snapshot = snapshot_formal_saves()
        for sub in (
            self.xdg_data_dir,
            self.xdg_config_dir,
            self.xdg_cache_dir,
            self.tmp_dir,
            self.reports_dir,
            self.shots_dir,
            self.py_scratch_dir,
        ):
            sub.mkdir(parents=True, exist_ok=True)
        # Pre-touch Xauthority inside scratch/tmp so xauth never complains or touches /tmp
        self.xauthority_file.touch(exist_ok=True)
        self._entered = True
        atexit.register(self._atexit_cleanup)
        return self

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        self.cleanup()

    def build_subprocess_env(self) -> dict[str, str]:
        """Construct an environment dict redirecting all XDG & TMP paths to scratch."""
        env = dict(os.environ)
        env["XDG_DATA_HOME"] = str(self.xdg_data_dir)
        env["XDG_CONFIG_HOME"] = str(self.xdg_config_dir)
        env["XDG_CACHE_HOME"] = str(self.xdg_cache_dir)
        env["TMPDIR"] = str(self.tmp_dir)
        env["TEMP"] = str(self.tmp_dir)
        env["TMP"] = str(self.tmp_dir)
        env["CHENYUAN_E2E_SCRATCH"] = str(self.run_dir)
        env["CHENYUAN_FORMAL_APP_DIR"] = str(FORMAL_APP_DIR)
        env["CHENYUAN_FORMAL_SAVES_DIR"] = str(FORMAL_SAVES_DIR)
        return env

    def verify_formal_saves_unchanged(self) -> tuple[bool, list[str]]:
        """Compare current formal saves/settings against ``pre_snapshot``."""
        self.post_snapshot = snapshot_formal_saves()
        diffs = diff_formal_snapshots(self.pre_snapshot, self.post_snapshot)
        return (len(diffs) == 0, diffs)

    def preserve_artifacts(self, dest_dir: Path) -> None:
        """Copy captured 1920x1080 screenshots and JSON/log reports to ``dest_dir``."""
        dest_dir.mkdir(parents=True, exist_ok=True)
        for src_sub, name in ((self.shots_dir, "shots"), (self.reports_dir, "reports")):
            if src_sub.exists() and any(src_sub.iterdir()):
                target_sub = dest_dir / name
                if target_sub.exists():
                    shutil.rmtree(target_sub)
                shutil.copytree(src_sub, target_sub)

    def cleanup(self) -> bool:
        """Delete the entire per-run scratch directory."""
        if self.run_dir.exists():
            shutil.rmtree(self.run_dir, ignore_errors=True)
        self.cleaned_up = not self.run_dir.exists()
        return self.cleaned_up

    def _atexit_cleanup(self) -> None:
        if self._entered and not self.cleaned_up:
            self.cleanup()
