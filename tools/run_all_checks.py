#!/usr/bin/env python3
"""Unified 4-Tier Opaque-Box E2E Test Runner CLI for 《尘缘问道》 (chenyuan-xianxia).

Usage examples:
    python3 tools/run_all_checks.py
    python3 tools/run_all_checks.py --all
    python3 tools/run_all_checks.py --tier 1
    python3 tools/run_all_checks.py --tier 2 --feature F5
    python3 tools/run_all_checks.py --target baseline
    python3 tools/run_all_checks.py --list
    python3 tools/run_all_checks.py --audit-quotas
    python3 tools/run_all_checks.py --all --json-out /home/antigravity/.gemini/jetski/scratch/e2e_report.json
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

sys.dont_write_bytecode = True
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.e2e.isolation_guard import IsolationConfigError  # noqa: E402
from tools.e2e.runner_core import execute_pipeline, parse_cli_to_config  # noqa: E402


def main(argv: list[str] | None = None) -> int:
    raw_argv = sys.argv[1:] if argv is None else argv
    try:
        cfg = parse_cli_to_config(raw_argv, REPO_ROOT)
    except SystemExit as exc:
        return int(exc.code) if exc.code is not None else 2
    except (ValueError, IsolationConfigError) as err:
        print(f"[CLI ERROR] {err}", file=sys.stderr)
        return 2

    try:
        return execute_pipeline(cfg)
    except KeyboardInterrupt:
        print("\n[INTERRUPTED] E2E run interrupted by user.", file=sys.stderr)
        return 2
    except Exception as exc:
        print(f"[FATAL INFRA ERROR] {type(exc).__name__}: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
