"""Opaque-box E2E test infrastructure package for 《尘缘问道》 (chenyuan-xianxia).

Exposes shared constants, feature normalization, and the ``CheckContext`` contract
used by ``tools/e2e/checks_w{1..4}_*.py`` modules.

Python Check Module Contract
----------------------------
Every ``tools/e2e/checks_w*.py`` module exposes::

    def get_checks() -> list[dict]:
        return [
            {
                "id": "T1-F05-01",
                "tier": 1,
                "feature": "F5",
                "target": "polish_r1",   # "baseline" | "polish_r1".."polish_r4"
                "title": "Human-readable check description",
                "fn": check_fn,          # Callable[[CheckContext], None]
            },
            ...
        ]
"""

from __future__ import annotations

import math
from pathlib import Path
from typing import Any, Callable

ALL_TIERS: tuple[int, ...] = (1, 2, 3, 4)
ALL_FEATURES: tuple[str, ...] = tuple(f"F{i}" for i in range(1, 17))
VALID_MODES: tuple[str, ...] = ("headless", "visual")

# Mandatory coverage quotas from TEST_INFRA.md & Orchestrator contract
MIN_TIER1_PER_FEATURE: int = 5
MIN_TIER2_PER_FEATURE: int = 5
MIN_TIER1_TOTAL: int = 80
MIN_TIER2_TOTAL: int = 80
MIN_TIER3_TOTAL: int = 16
MIN_TIER4_TOTAL: int = 8
MIN_GRAND_TOTAL: int = 184

FEATURE_TITLES: dict[str, str] = {
    "F1": "Seamless RTwP Combat, Auto-Attack, GCD & Threat",
    "F2": "Five-Element Counter Ward-Break & Generative Synergy",
    "F3": "Tactical Pause (Space), Party AI & Dual Bond Ultimate",
    "F4": "Qimen Permanent Aura Formations",
    "F5": "Polish R1: Combat VFX, Hit-Feel & Artifact HUD",
    "F6": "Polish R2: Multi-Pose Character & Giant Boss Animations",
    "F7": "3-Tier Narrative Stage, Portrait Expressions & Karma Seals",
    "F8": "Seven Realms, 3-Bucket Math (45/35/20) & Ink Meridian Page",
    "F9": "5-Slot Artifacts, Blue Skills, Sword Box & Embossed Slots",
    "F10": "Sole Spirit-Stone Economy, Flickering Alchemy & Purify",
    "F11": "Thread-Bound Xuan Tome Frame, RMB Ripple & Hover Outline",
    "F12": "3-Zone Seamless Exploration, Stealth & Spirit Steles",
    "F13": "Polish R4: Town/Pass/Cave Architectural Fullness",
    "F14": "Polish R4: Stage C PointLight2D, Wet Stone & Occlusion",
    "F15": "Save Safety, NotifyHub, InputRouter, Recap, Audio & Manifest",
    "F16": "Chunked Web/Desktop Exports (<85MB), Release & Scope Lock",
}


def normalize_feature_id(raw: str | int) -> str:
    """Normalize 'F1', 'f01', '01', or 1 into canonical 'F1'..'F16'."""
    token = str(raw).strip().upper()
    if token.startswith("F"):
        token = token[1:]
    if not token.isdigit():
        raise ValueError(f"Invalid feature identifier '{raw}' (expected F1..F16)")
    num = int(token)
    if not (1 <= num <= 16):
        raise ValueError(f"Feature number out of range in '{raw}' (expected F1..F16)")
    return f"F{num}"


class CheckContext:
    """Execution & non-aborting assertion context passed to Python E2E checks.

    Method names mirror ``project/tests/e2e_harness.gd`` so Python and GDScript
    suites share an identical mental model and reporting schema.
    """

    def __init__(self, repo_root: Path, scratch_dir: Path, case_id: str = "") -> None:
        self.repo_root: Path = repo_root
        self.project_dir: Path = repo_root / "project"
        self._base_scratch_dir: Path = scratch_dir
        self.case_id: str = case_id
        self._failures: list[str] = []
        self._metrics: dict[str, Any] = {}

    @property
    def scratch_dir(self) -> Path:
        """Lazily materialized isolated scratch directory for this check."""
        self._base_scratch_dir.mkdir(parents=True, exist_ok=True)
        return self._base_scratch_dir

    @property
    def failures(self) -> list[str]:
        return list(self._failures)

    @property
    def metrics(self) -> dict[str, Any]:
        return dict(self._metrics)

    def fail_msg(self, msg: str) -> None:
        self._failures.append(str(msg))

    def assert_true(self, cond: Any, msg: str) -> None:
        if not bool(cond):
            self._failures.append(str(msg))

    def assert_false(self, cond: Any, msg: str) -> None:
        if bool(cond):
            self._failures.append(str(msg))

    def assert_eq(self, actual: Any, expected: Any, msg: str) -> None:
        if actual != expected:
            self._failures.append(f"{msg} [expected={expected!r}, actual={actual!r}]")

    def assert_ne(self, actual: Any, unexpected: Any, msg: str) -> None:
        if actual == unexpected:
            self._failures.append(f"{msg} [unexpected={actual!r}]")

    def assert_approx(self, actual: float, expected: float, eps: float, msg: str) -> None:
        val_a = float(actual)
        val_e = float(expected)
        val_eps = float(eps)
        if math.isnan(val_a) or abs(val_a - val_e) > val_eps:
            self._failures.append(
                f"{msg} [expected={val_e:.4f}±{val_eps:.4f}, actual={val_a:.4f}]"
            )

    def assert_gt(self, actual: float | int, threshold: float | int, msg: str) -> None:
        if not (actual > threshold):
            self._failures.append(f"{msg} [expected > {threshold}, actual={actual}]")

    def assert_ge(self, actual: float | int, threshold: float | int, msg: str) -> None:
        if not (actual >= threshold):
            self._failures.append(f"{msg} [expected >= {threshold}, actual={actual}]")

    def assert_lt(self, actual: float | int, threshold: float | int, msg: str) -> None:
        if not (actual < threshold):
            self._failures.append(f"{msg} [expected < {threshold}, actual={actual}]")

    def assert_le(self, actual: float | int, threshold: float | int, msg: str) -> None:
        if not (actual <= threshold):
            self._failures.append(f"{msg} [expected <= {threshold}, actual={actual}]")

    def assert_str_contains(self, haystack: str, needle: str, msg: str) -> None:
        if str(needle) not in str(haystack):
            self._failures.append(f"{msg} [missing {needle!r} in {haystack!r}]")

    def record_metric(self, key: str, val: Any) -> None:
        self._metrics[str(key)] = val


CheckFn = Callable[[CheckContext], None]


def make_check(
    case_id: str,
    tier: int,
    feature: str,
    target: str,
    title: str,
    fn: CheckFn,
) -> dict[str, Any]:
    """Convenience constructor for a ``get_checks()`` entry dictionary."""
    return {
        "id": str(case_id).strip(),
        "tier": int(tier),
        "feature": normalize_feature_id(feature),
        "target": str(target).strip(),
        "title": str(title).strip(),
        "fn": fn,
    }


__all__ = [
    "ALL_FEATURES",
    "ALL_TIERS",
    "CheckContext",
    "CheckFn",
    "FEATURE_TITLES",
    "MIN_GRAND_TOTAL",
    "MIN_TIER1_PER_FEATURE",
    "MIN_TIER1_TOTAL",
    "MIN_TIER2_PER_FEATURE",
    "MIN_TIER2_TOTAL",
    "MIN_TIER3_TOTAL",
    "MIN_TIER4_TOTAL",
    "VALID_MODES",
    "make_check",
    "normalize_feature_id",
]
