"""Core orchestration, auto-discovery, 4-stage batching & quota auditing for E2E checks."""

from __future__ import annotations

import importlib.util
import json
import os
import re
import signal
import subprocess
import sys
import time
import traceback
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"

from tools.e2e import (
    ALL_FEATURES,
    ALL_TIERS,
    FEATURE_TITLES,
    MIN_GRAND_TOTAL,
    MIN_TIER1_PER_FEATURE,
    MIN_TIER1_TOTAL,
    MIN_TIER2_PER_FEATURE,
    MIN_TIER2_TOTAL,
    MIN_TIER3_TOTAL,
    MIN_TIER4_TOTAL,
    VALID_MODES,
    CheckContext,
    normalize_feature_id,
)
from tools.e2e.isolation_guard import (
    FORMAL_SAVES_DIR,
    IsolationConfigError,
    IsolationGuard,
    validate_output_path,
)

DEFAULT_GODOT_BIN: Path = Path("/home/antigravity/.local/bin/godot")
XVFB_RUN_BIN: Path = Path("/usr/bin/xvfb-run")

MODE_HEADER_RE = re.compile(r"^\s*#\s*@e2e_mode\s*:\s*(\S+)\s*$", re.IGNORECASE)
TIER_HEADER_RE = re.compile(r"^\s*#\s*@e2e_tier\s*:\s*(\d+)\s*$", re.IGNORECASE)
FEAT_HEADER_RE = re.compile(r"^\s*#\s*@e2e_features\s*:\s*(.+?)\s*$", re.IGNORECASE)

FATAL_GODOT_LOG_PATTERNS: tuple[str, ...] = (
    "SCRIPT ERROR:",
    "Parse Error:",
    "Compile Error:",
    "SHADER ERROR:",
    "FATAL_ISOLATION_BREACH",
)


@dataclass
class GDSuiteMeta:
    abs_path: Path
    rel_path: str
    res_path: str
    tier_dir: int
    mode: str  # "headless" | "visual"
    header_features: list[str] = field(default_factory=list)


@dataclass
class RunConfig:
    repo_root: Path
    tiers: list[int]
    features: list[str]
    targets: list[str]
    cases: list[str]
    list_only: bool = False
    audit_quotas: bool = False
    json_out: Path | None = None
    keep_artifacts: Path | None = None
    verbose: bool = False
    godot_bin: Path = DEFAULT_GODOT_BIN


def resolve_godot_bin() -> Path:
    env_bin = os.environ.get("GODOT_BIN", "").strip()
    if env_bin:
        p = Path(env_bin).expanduser()
        if p.is_file():
            return p
    if DEFAULT_GODOT_BIN.is_file():
        return DEFAULT_GODOT_BIN
    raise FileNotFoundError(f"Godot 4.3 binary not found at {DEFAULT_GODOT_BIN}")


def _run_subprocess_grouped(
    cmd: list[str],
    *,
    cwd: Path,
    env: dict[str, str],
    timeout_sec: float,
) -> tuple[int, str, bool]:
    """Run subprocess in its own process group so timeouts cleanly kill Xvfb + Godot."""
    proc = subprocess.Popen(
        cmd,
        cwd=str(cwd),
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        start_new_session=True,
    )
    timed_out = False
    try:
        out, _ = proc.communicate(timeout=timeout_sec)
    except subprocess.TimeoutExpired:
        timed_out = True
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        out, _ = proc.communicate()
    return int(proc.returncode or 0), out or "", timed_out


def _needs_godot_import(project_dir: Path) -> bool:
    godot_dir = project_dir / ".godot"
    class_cache = godot_dir / "global_script_class_cache.cfg"
    imported_dir = godot_dir / "imported"
    if not class_cache.is_file() or not imported_dir.is_dir():
        return True
    if not any(imported_dir.iterdir()):
        return True

    cache_mtime = class_cache.stat().st_mtime_ns
    src_dir = project_dir / "src"
    if src_dir.is_dir():
        for gd_file in src_dir.rglob("*.gd"):
            if gd_file.stat().st_mtime_ns > cache_mtime:
                return True
    return False


def ensure_godot_import_cache(
    project_dir: Path,
    godot_bin: Path,
    env: dict[str, str],
    *,
    verbose: bool = False,
) -> tuple[bool, str]:
    """Stage 0: Ensure ``project/.godot/`` class & import caches are warm."""
    if not _needs_godot_import(project_dir):
        return True, ""

    cmd = [
        str(godot_bin),
        "--headless",
        "--audio-driver",
        "Dummy",
        "--path",
        str(project_dir),
        "--import",
    ]
    rc, out, timed_out = _run_subprocess_grouped(
        cmd,
        cwd=project_dir,
        env=env,
        timeout_sec=120.0,
    )
    if verbose and out.strip():
        print(out)
    if timed_out:
        return False, "Stage 0 Godot --import timed out after 120s"
    if rc != 0:
        return False, f"Stage 0 Godot --import exited with code {rc}:\n{out[-1500:]}"
    return True, out


def discover_python_checks(repo_root: Path) -> tuple[list[dict[str, Any]], list[str]]:
    """Auto-discover ``tools/e2e/checks_*.py`` (and ``host_compliance_checks.py`` if present)."""
    e2e_dir = repo_root / "tools" / "e2e"
    candidates = sorted(e2e_dir.glob("checks_*.py"))
    extra = e2e_dir / "host_compliance_checks.py"
    if extra.is_file() and extra not in candidates:
        candidates.append(extra)

    discovered: list[dict[str, Any]] = []
    errors: list[str] = []

    if str(repo_root) not in sys.path:
        sys.path.insert(0, str(repo_root))

    for mod_path in candidates:
        rel_suite = mod_path.relative_to(repo_root).as_posix()
        mod_name = f"tools.e2e.{mod_path.stem}"
        try:
            spec = importlib.util.spec_from_file_location(mod_name, mod_path)
            if spec is None or spec.loader is None:
                errors.append(f"Cannot load Python check module spec: {rel_suite}")
                continue
            module = importlib.util.module_from_spec(spec)
            sys.modules[mod_name] = module
            spec.loader.exec_module(module)
            get_checks_fn = getattr(module, "get_checks", None)
            if not callable(get_checks_fn):
                errors.append(f"Module '{rel_suite}' does not expose callable get_checks()")
                continue
            raw_list = get_checks_fn()
            if not isinstance(raw_list, list):
                errors.append(f"'{rel_suite}:get_checks()' must return list[dict]")
                continue

            for idx, entry in enumerate(raw_list):
                if not isinstance(entry, dict):
                    errors.append(f"'{rel_suite}' check #{idx} is not a dict")
                    continue
                cid = str(entry.get("id", "")).strip()
                tier = int(entry.get("tier", 0))
                feat = normalize_feature_id(entry.get("feature", ""))
                target = str(entry.get("target", "baseline")).strip()
                title = str(entry.get("title", "")).strip()
                fn = entry.get("fn")
                if not cid or tier not in ALL_TIERS or not title or not callable(fn):
                    errors.append(
                        f"Invalid check schema in '{rel_suite}' at index {idx} (id={cid!r}, tier={tier})"
                    )
                    continue
                discovered.append(
                    {
                        "id": cid,
                        "tier": tier,
                        "feature": feat,
                        "target": target or "baseline",
                        "mode": "python",
                        "suite": rel_suite,
                        "title": title,
                        "fn": fn,
                    }
                )
        except Exception as exc:
            errors.append(
                f"Failed loading Python check module '{rel_suite}': {exc}\n{traceback.format_exc()}"
            )

    return discovered, errors


def discover_gdscript_suites(repo_root: Path) -> tuple[list[GDSuiteMeta], list[str]]:
    """Auto-discover ``project/tests/tier{1..4}/test_*.gd`` and parse ``@e2e_mode`` headers."""
    tests_dir = repo_root / "project" / "tests"
    suites: list[GDSuiteMeta] = []
    errors: list[str] = []

    for tier_num in ALL_TIERS:
        tdir = tests_dir / f"tier{tier_num}"
        if not tdir.is_dir():
            continue
        for gd_path in sorted(tdir.glob("test_*.gd")):
            rel_repo = gd_path.relative_to(repo_root).as_posix()
            res_path = "res://" + gd_path.relative_to(repo_root / "project").as_posix()
            mode = "headless"
            header_feats: list[str] = []
            try:
                head_lines = gd_path.read_text(encoding="utf-8").splitlines()[:25]
            except OSError as exc:
                errors.append(f"Cannot read GDScript suite '{rel_repo}': {exc}")
                continue

            for line in head_lines:
                m_mode = MODE_HEADER_RE.match(line)
                if m_mode:
                    parsed_mode = m_mode.group(1).strip().lower()
                    if parsed_mode not in VALID_MODES:
                        errors.append(
                            f"Invalid '# @e2e_mode: {parsed_mode}' in '{rel_repo}' "
                            f"(expected one of {VALID_MODES})"
                        )
                    else:
                        mode = parsed_mode
                m_feat = FEAT_HEADER_RE.match(line)
                if m_feat:
                    for tok in re.split(r"[,\s]+", m_feat.group(1).strip()):
                        if tok:
                            try:
                                header_feats.append(normalize_feature_id(tok))
                            except ValueError as v_err:
                                errors.append(f"In '{rel_repo}': {v_err}")

            suites.append(
                GDSuiteMeta(
                    abs_path=gd_path,
                    rel_path=rel_repo,
                    res_path=res_path,
                    tier_dir=tier_num,
                    mode=mode,
                    header_features=header_feats,
                )
            )
    return suites, errors


def run_gdscript_check_only_gate(
    project_dir: Path,
    godot_bin: Path,
    env: dict[str, str],
    *,
    verbose: bool = False,
) -> tuple[bool, list[str]]:
    """Stage 2a: Verify 0 errors & 0 warnings via ``-d --check-only`` on core harness scripts.

    Note: Godot 4.3 ``--check-only`` runs prior to ``SceneTree::initialize()`` (before
    ``[autoload]`` globals exist). Core harness scripts ``e2e_harness.gd`` and
    ``e2e_batch_runner.gd`` are engineered to pass ``-d --check-only`` directly, while
    suite scripts ``res://tests/tier{1..4}/test_*.gd`` (which reference ``CampaignState``,
    ``DataDB``, etc.) are compiled with ``-d`` strict warning/type enforcement in Stage 2b
    immediately after ``SceneTree::initialize()``.
    """
    errors: list[str] = []
    core_scripts = ["res://tests/e2e_harness.gd", "res://tests/e2e_batch_runner.gd"]

    for res_path in core_scripts:
        cmd = [
            str(godot_bin),
            "--headless",
            "-d",
            "--audio-driver",
            "Dummy",
            "--path",
            str(project_dir),
            "--check-only",
            "-s",
            res_path,
        ]
        rc, out, timed_out = _run_subprocess_grouped(
            cmd,
            cwd=project_dir,
            env=env,
            timeout_sec=30.0,
        )
        if verbose and out.strip():
            print(out)
        if timed_out:
            errors.append(f"GDScript --check-only timed out on {res_path}")
            continue

        bad_lines: list[str] = []
        for line in out.splitlines():
            stripped = line.strip()
            if (
                "SCRIPT ERROR:" in stripped
                or "Parse Error:" in stripped
                or "Compile Error:" in stripped
                or "WARNING:" in stripped
                or "UNSAFE_PROPERTY_ACCESS" in stripped
                or "UNSAFE_METHOD_ACCESS" in stripped
                or "UNTYPED_DECLARATION" in stripped
            ):
                bad_lines.append(stripped)

        if rc != 0 or bad_lines:
            detail = "\n  ".join(bad_lines[:12]) if bad_lines else out.strip()[-600:]
            errors.append(
                f"Strict GDScript --check-only failed for {res_path} (exit={rc}):\n  {detail}"
            )

    return (len(errors) == 0, errors)


def _case_matches_config(case_meta: dict[str, Any], cfg: RunConfig) -> bool:
    if cfg.tiers and int(case_meta.get("tier", 0)) not in cfg.tiers:
        return False
    if cfg.features and str(case_meta.get("feature", "")) not in cfg.features:
        return False
    if cfg.targets and str(case_meta.get("target", "")) not in cfg.targets:
        return False
    if cfg.cases and str(case_meta.get("id", "")) not in cfg.cases:
        return False
    return True


def _suite_matches_cli_filters(suite: GDSuiteMeta, cfg: RunConfig) -> bool:
    """Pre-filter GDScript suites using tier_dir and non-empty header_features."""
    if cfg.tiers and suite.tier_dir not in cfg.tiers:
        return False
    if cfg.features and suite.header_features:
        if not any(feat in cfg.features for feat in suite.header_features):
            return False
    return True


def _parse_batch_log_errors(log_text: str) -> tuple[dict[str, list[str]], list[str], str]:
    """Attribute unexpected Godot script/engine errors to active cases or batch level.

    Returns ``(per_case_errors, batch_level_errors, last_started_suite)``.
    """
    active_suite = ""
    active_case = ""
    allowed_by_case: dict[str, list[str]] = {}
    per_case_errors: dict[str, list[str]] = {}
    batch_errors: list[str] = []

    for raw_line in log_text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("@@E2E_SUITE_START@@"):
            active_suite = line.split("@@E2E_SUITE_START@@", 1)[1].strip()
            continue
        if line.startswith("@@E2E_SUITE_END@@"):
            active_suite = ""
            continue
        if line.startswith("@@E2E_CASE_START@@"):
            active_case = line.split("@@E2E_CASE_START@@", 1)[1].strip()
            continue
        if line.startswith("@@E2E_CASE_END@@"):
            active_case = ""
            continue
        if line.startswith("@@E2E_ALLOW_ERR@@"):
            parts = line.split("@@")
            if len(parts) >= 4:
                cid = parts[2].strip()
                pat = parts[3].strip()
                if cid and pat:
                    allowed_by_case.setdefault(cid, []).append(pat)
            continue

        is_fatal_pat = any(pat in line for pat in FATAL_GODOT_LOG_PATTERNS)
        is_case_cpp_err = bool(active_case) and line.startswith("ERROR:")
        if is_fatal_pat or is_case_cpp_err:
            if active_case:
                pats = allowed_by_case.get(active_case, [])
                if any(p in line for p in pats):
                    continue
                per_case_errors.setdefault(active_case, []).append(line)
            else:
                batch_errors.append(f"{active_suite or 'batch'}: {line}")

    return per_case_errors, batch_errors, active_suite


def _build_godot_batch_cmd(
    *,
    mode: str,
    project_dir: Path,
    godot_bin: Path,
    guard: IsolationGuard,
    suites_file: Path,
    report_json: Path,
    cfg: RunConfig,
    list_only: bool = False,
) -> list[str]:
    user_args: list[str] = [
        "--",
        "--mode",
        mode,
        "--suites-file",
        str(suites_file),
        "--report-json",
        str(report_json),
        "--scratch-dir",
        str(guard.run_dir),
    ]
    if list_only:
        user_args.append("--list-only")
    else:
        if cfg.tiers:
            user_args.extend(["--tiers", ",".join(str(t) for t in cfg.tiers)])
        if cfg.features:
            user_args.extend(["--features", ",".join(cfg.features)])
        if cfg.targets:
            user_args.extend(["--targets", ",".join(cfg.targets)])
        if cfg.cases:
            user_args.extend(["--cases", ",".join(cfg.cases)])

    if mode == "visual" and not list_only:
        if not XVFB_RUN_BIN.is_file():
            raise FileNotFoundError(f"xvfb-run not found at {XVFB_RUN_BIN}")
        return [
            str(XVFB_RUN_BIN),
            "-a",
            "-f",
            str(guard.xauthority_file),
            "-s",
            "-screen 0 1920x1080x24",
            str(godot_bin),
            "--path",
            str(project_dir),
            "--display-driver",
            "x11",
            "--rendering-driver",
            "opengl3",
            "--audio-driver",
            "Dummy",
            "--disable-vsync",
            "--resolution",
            "1920x1080",
            "--position",
            "0,0",
            "-s",
            "res://tests/e2e_batch_runner.gd",
            *user_args,
        ]

    headless_cmd = [str(godot_bin), "--headless"]
    if list_only:
        headless_cmd.append("-d")
    headless_cmd.extend(
        [
            "--audio-driver",
            "Dummy",
            "--path",
            str(project_dir),
            "-s",
            "res://tests/e2e_batch_runner.gd",
            *user_args,
        ]
    )
    return headless_cmd


def _execute_gd_batch_once(
    *,
    tag: str,
    mode: str,
    suites: list[GDSuiteMeta],
    project_dir: Path,
    godot_bin: Path,
    guard: IsolationGuard,
    env: dict[str, str],
    cfg: RunConfig,
    list_only: bool = False,
) -> tuple[bool, list[dict[str, Any]], list[str]]:
    """Execute one GDScript batch and return ``(ok, case_records, batch_errors)``."""
    suites_file = guard.reports_dir / f"{tag}_suites.json"
    report_json = guard.reports_dir / f"{tag}_report.json"
    log_file = guard.reports_dir / f"{tag}.log"

    suites_payload = [{"res_path": s.res_path, "mode": s.mode} for s in suites]
    suites_file.write_text(json.dumps(suites_payload, indent=2), encoding="utf-8")
    if report_json.exists():
        report_json.unlink()

    cmd = _build_godot_batch_cmd(
        mode=mode,
        project_dir=project_dir,
        godot_bin=godot_bin,
        guard=guard,
        suites_file=suites_file,
        report_json=report_json,
        cfg=cfg,
        list_only=list_only,
    )
    timeout_sec = (
        max(300.0, 90.0 * len(suites))
        if (mode == "visual" and not list_only)
        else (max(180.0, 30.0 * len(suites)) if not list_only else 180.0)
    )
    rc, log_out, timed_out = _run_subprocess_grouped(
        cmd,
        cwd=project_dir,
        env=env,
        timeout_sec=timeout_sec,
    )
    log_file.write_text(log_out, encoding="utf-8")
    if cfg.verbose and log_out.strip():
        print(log_out)

    per_case_errs, batch_errs, last_suite = _parse_batch_log_errors(log_out)
    if list_only:
        lines = log_out.splitlines()
        for idx_l, raw_l in enumerate(lines):
            s_l = raw_l.strip()
            if "WARNING:" in s_l or "UNSAFE_PROPERTY_ACCESS" in s_l or "UNSAFE_METHOD_ACCESS" in s_l:
                ctx_window = " ".join(lines[idx_l : min(len(lines), idx_l + 3)])
                if "res://tests/" in ctx_window:
                    batch_errs.append(f"Strict GDScript warning in test suite: {ctx_window.strip()}")

    if timed_out:
        batch_errs.append(
            f"Batch '{tag}' ({mode}) timed out after {timeout_sec:.0f}s "
            f"(active_suite={last_suite or 'unknown'})"
        )
        return False, [], batch_errs

    if rc != 0 or not report_json.is_file():
        tail = "\n".join(log_out.strip().splitlines()[-15:])
        batch_errs.append(
            f"Batch '{tag}' ({mode}) failed (rc={rc}, report_exists={report_json.is_file()}, "
            f"active_suite={last_suite or 'unknown'}):\n{tail}"
        )
        return False, [], batch_errs

    data = json.loads(report_json.read_text(encoding="utf-8"))
    if not bool(data.get("isolation_ok", True)):
        for iso_e in data.get("isolation_errors", []):
            batch_errs.append(f"GDScript isolation breach: {iso_e}")
    for s_err in data.get("suite_errors", []):
        batch_errs.append(f"Suite error in {s_err.get('suite')}: {s_err.get('message')}")

    cases_out: list[dict[str, Any]] = list(data.get("cases", []))
    for rec in cases_out:
        cid = str(rec.get("id", ""))
        if cid in per_case_errs:
            rec["status"] = "ERROR"
            joined = " | ".join(per_case_errs[cid][:4])
            prev_msg = str(rec.get("message", "")).strip()
            rec["message"] = f"{prev_msg}; EngineError: {joined}" if prev_msg else f"EngineError: {joined}"

    return (len(batch_errs) == 0, cases_out, batch_errs)


def run_gd_suites_with_fallback(
    *,
    stage_name: str,
    mode: str,
    suites: list[GDSuiteMeta],
    project_dir: Path,
    godot_bin: Path,
    guard: IsolationGuard,
    env: dict[str, str],
    cfg: RunConfig,
) -> tuple[list[dict[str, Any]], list[str]]:
    """Run all suites of ``mode`` in 1 batch; fall back per-suite if a crash occurs."""
    if not suites:
        return [], []

    ok, records, errs = _execute_gd_batch_once(
        tag=stage_name,
        mode=mode,
        suites=suites,
        project_dir=project_dir,
        godot_bin=godot_bin,
        guard=guard,
        env=env,
        cfg=cfg,
        list_only=False,
    )
    if ok:
        return records, []

    if len(suites) == 1:
        s = suites[0]
        synth = {
            "id": f"ERROR-{s.abs_path.stem.upper()}",
            "tier": s.tier_dir,
            "feature": s.header_features[0] if s.header_features else "F1",
            "target": "infra",
            "mode": mode,
            "suite": s.rel_path,
            "title": f"Suite execution crash/error in {s.rel_path}",
            "status": "ERROR",
            "duration_ms": 0.0,
            "message": "; ".join(errs),
            "metrics": {},
        }
        return (records if records else [synth]), errs

    # Fallback: isolate each suite in its own process so healthy suites still report cleanly
    recovered_records: list[dict[str, Any]] = []
    fallback_errors: list[str] = []
    for idx, s in enumerate(suites):
        s_ok, s_recs, s_errs = _execute_gd_batch_once(
            tag=f"{stage_name}_fallback_{idx}_{s.abs_path.stem}",
            mode=mode,
            suites=[s],
            project_dir=project_dir,
            godot_bin=godot_bin,
            guard=guard,
            env=env,
            cfg=cfg,
            list_only=False,
        )
        if s_ok:
            recovered_records.extend(s_recs)
        else:
            fallback_errors.extend(s_errs)
            if s_recs:
                recovered_records.extend(s_recs)
            else:
                recovered_records.append(
                    {
                        "id": f"ERROR-{s.abs_path.stem.upper()}",
                        "tier": s.tier_dir,
                        "feature": s.header_features[0] if s.header_features else "F1",
                        "target": "infra",
                        "mode": mode,
                        "suite": s.rel_path,
                        "title": f"Suite execution crash/error in {s.rel_path}",
                        "status": "ERROR",
                        "duration_ms": 0.0,
                        "message": "; ".join(s_errs),
                        "metrics": {},
                    }
                )
    return recovered_records, fallback_errors


def run_python_checks(
    checks: list[dict[str, Any]],
    cfg: RunConfig,
    guard: IsolationGuard,
) -> list[dict[str, Any]]:
    """Stage 1: Execute selected in-process Python checks with isolated scratch."""
    results: list[dict[str, Any]] = []
    for chk in checks:
        if not _case_matches_config(chk, cfg):
            continue
        cid = str(chk["id"])
        safe_id = re.sub(r"[^A-Za-z0-9_.-]+", "_", cid)
        ctx = CheckContext(
            repo_root=cfg.repo_root,
            scratch_dir=guard.py_scratch_dir / safe_id,
            case_id=cid,
        )
        t0 = time.perf_counter()
        status = "PASS"
        msg = ""
        try:
            chk["fn"](ctx)
            if ctx.failures:
                status = "FAIL"
                msg = "; ".join(ctx.failures)
        except AssertionError as a_err:
            all_fails = [*ctx.failures, str(a_err) or "AssertionError"]
            status = "FAIL"
            msg = "; ".join(all_fails)
        except Exception as exc:
            status = "ERROR"
            msg = f"Unhandled {type(exc).__name__}: {exc}"

        dur_ms = round((time.perf_counter() - t0) * 1000.0, 2)
        results.append(
            {
                "id": cid,
                "tier": int(chk["tier"]),
                "feature": str(chk["feature"]),
                "target": str(chk["target"]),
                "mode": "python",
                "suite": str(chk["suite"]),
                "title": str(chk["title"]),
                "status": status,
                "duration_ms": dur_ms,
                "message": msg,
                "metrics": ctx.metrics,
            }
        )
    return results


def find_duplicate_ids(items: list[dict[str, Any]]) -> dict[str, list[str]]:
    by_id: dict[str, list[str]] = {}
    for item in items:
        cid = str(item.get("id", ""))
        suite = str(item.get("suite", ""))
        by_id.setdefault(cid, []).append(suite)
    return {cid: suites for cid, suites in by_id.items() if len(suites) > 1}


def evaluate_quotas(all_defs: list[dict[str, Any]]) -> tuple[bool, dict[str, Any]]:
    """Evaluate mandatory 4-tier & per-feature F1..F16 coverage quotas."""
    dups = find_duplicate_ids(all_defs)
    per_feat: dict[str, dict[str, int]] = {
        f: {"t1": 0, "t2": 0, "t3": 0, "t4": 0, "baseline": 0, "polish": 0, "total": 0}
        for f in ALL_FEATURES
    }
    tier_totals: dict[int, int] = {1: 0, 2: 0, 3: 0, 4: 0}

    for d in all_defs:
        t = int(d.get("tier", 0))
        f = str(d.get("feature", ""))
        targ = str(d.get("target", "baseline"))
        if t in tier_totals:
            tier_totals[t] += 1
        if f in per_feat:
            if t in (1, 2, 3, 4):
                per_feat[f][f"t{t}"] += 1
            if targ == "baseline":
                per_feat[f]["baseline"] += 1
            else:
                per_feat[f]["polish"] += 1
            per_feat[f]["total"] += 1

    violations: list[str] = []
    if dups:
        for cid, suites in sorted(dups.items()):
            violations.append(f"Duplicate test ID '{cid}' in {suites}")

    grand_total = len(all_defs)
    if grand_total < MIN_GRAND_TOTAL:
        violations.append(f"Grand total cases {grand_total} < required {MIN_GRAND_TOTAL}")
    if tier_totals[1] < MIN_TIER1_TOTAL:
        violations.append(f"Tier 1 total {tier_totals[1]} < required {MIN_TIER1_TOTAL}")
    if tier_totals[2] < MIN_TIER2_TOTAL:
        violations.append(f"Tier 2 total {tier_totals[2]} < required {MIN_TIER2_TOTAL}")
    if tier_totals[3] < MIN_TIER3_TOTAL:
        violations.append(f"Tier 3 total {tier_totals[3]} < required {MIN_TIER3_TOTAL}")
    if tier_totals[4] < MIN_TIER4_TOTAL:
        violations.append(f"Tier 4 total {tier_totals[4]} < required {MIN_TIER4_TOTAL}")

    for feat in ALL_FEATURES:
        fc = per_feat[feat]
        if fc["t1"] < MIN_TIER1_PER_FEATURE:
            violations.append(
                f"{feat} Tier 1 count {fc['t1']} < required {MIN_TIER1_PER_FEATURE}"
            )
        if fc["t2"] < MIN_TIER2_PER_FEATURE:
            violations.append(
                f"{feat} Tier 2 count {fc['t2']} < required {MIN_TIER2_PER_FEATURE}"
            )

    summary = {
        "passed": len(violations) == 0,
        "grand_total": grand_total,
        "tier_totals": tier_totals,
        "per_feature": per_feat,
        "duplicate_ids": dups,
        "violations": violations,
    }
    return (len(violations) == 0, summary)


def _print_discovery_tables(all_defs: list[dict[str, Any]], quota_info: dict[str, Any]) -> None:
    print("\n=== Discovered Test Cases ===")
    for d in all_defs:
        print(
            f"[LIST] {d['id']:<14} | Tier {d['tier']} | {d['feature']:<3} | "
            f"{d['target']:<9} | {d['mode']:<8} | {d['suite']} | {d['title']}"
        )

    print("\n=== Per-Feature F1–F16 Quota Table ===")
    header = (
        f"{'Feat':<4} | {'T1':>4} | {'T2':>4} | {'T3':>4} | {'T4':>4} | "
        f"{'Baseline':>8} | {'Polish':>6} | {'Total':>5} | {'T1>=5 & T2>=5':<13} | Feature"
    )
    print(header)
    print("-" * len(header))
    pf = quota_info["per_feature"]
    for feat in ALL_FEATURES:
        row = pf[feat]
        ok_f = row["t1"] >= MIN_TIER1_PER_FEATURE and row["t2"] >= MIN_TIER2_PER_FEATURE
        badge = "OK" if ok_f else "SHORTFALL"
        print(
            f"{feat:<4} | {row['t1']:>4} | {row['t2']:>4} | {row['t3']:>4} | {row['t4']:>4} | "
            f"{row['baseline']:>8} | {row['polish']:>6} | {row['total']:>5} | {badge:<13} | "
            f"{FEATURE_TITLES.get(feat, '')}"
        )

    tt = quota_info["tier_totals"]
    print("-" * len(header))
    print(
        f"TOT  | {tt[1]:>4} | {tt[2]:>4} | {tt[3]:>4} | {tt[4]:>4} | "
        f"{sum(pf[f]['baseline'] for f in ALL_FEATURES):>8} | "
        f"{sum(pf[f]['polish'] for f in ALL_FEATURES):>6} | {quota_info['grand_total']:>5} | "
        f"{'QUOTA PASS' if quota_info['passed'] else 'QUOTA INCOMPLETE'}"
    )


def _print_execution_report(
    records: list[dict[str, Any]],
    *,
    saves_ok: bool,
    save_diffs: list[str],
    scratch_cleaned: bool,
    wall_ms: float,
) -> None:
    print("\n=== 1. Per-Test Stream ===")
    for r in records:
        st = str(r.get("status", "ERROR"))
        dur = float(r.get("duration_ms", 0.0))
        print(
            f"[{st:<5}] {r['id']:<14} | Tier {r['tier']} | {r['feature']:<3} | "
            f"{r['target']:<9} | {dur:>7.1f}ms | {r['title']}"
        )
        if st != "PASS" and r.get("message"):
            print(f"        └─ {r['message']}")

    # 2. Per-Feature F1..F16 Coverage & Status Table
    print("\n=== 2. Per-Feature F1–F16 Coverage & Status Table ===")
    hdr = (
        f"{'Feat':<4} | {'T1(P/T)':>8} | {'T2(P/T)':>8} | {'T3(P/T)':>8} | {'T4(P/T)':>8} | "
        f"{'Baseline(P/T)':>13} | {'Polish(P/T)':>11} | {'Total(P/F/E)':>12}"
    )
    print(hdr)
    print("-" * len(hdr))
    for feat in ALL_FEATURES:
        f_recs = [r for r in records if r.get("feature") == feat]
        t_cells: list[str] = []
        for t in ALL_TIERS:
            tr_list = [r for r in f_recs if int(r.get("tier", 0)) == t]
            tp = sum(1 for r in tr_list if r.get("status") == "PASS")
            t_cells.append(f"{tp}/{len(tr_list)}")
        base_list = [r for r in f_recs if r.get("target") == "baseline"]
        bp = sum(1 for r in base_list if r.get("status") == "PASS")
        pol_list = [r for r in f_recs if r.get("target") != "baseline"]
        pp = sum(1 for r in pol_list if r.get("status") == "PASS")
        tot_p = sum(1 for r in f_recs if r.get("status") == "PASS")
        tot_f = sum(1 for r in f_recs if r.get("status") == "FAIL")
        tot_e = sum(1 for r in f_recs if r.get("status") == "ERROR")
        print(
            f"{feat:<4} | {t_cells[0]:>8} | {t_cells[1]:>8} | {t_cells[2]:>8} | {t_cells[3]:>8} | "
            f"{f'{bp}/{len(base_list)}':>13} | {f'{pp}/{len(pol_list)}':>11} | "
            f"{f'{tot_p}/{tot_f}/{tot_e}':>12}"
        )

    # 3. Per-Tier Summary Table
    print("\n=== 3. Per-Tier Summary Table ===")
    thdr = f"{'Tier':<8} | {'Selected':>8} | {'PASS':>6} | {'FAIL':>6} | {'ERROR':>6} | {'Duration':>10} | {'Status':<8}"
    print(thdr)
    print("-" * len(thdr))
    for t in ALL_TIERS:
        t_recs = [r for r in records if int(r.get("tier", 0)) == t]
        sel = len(t_recs)
        tp = sum(1 for r in t_recs if r.get("status") == "PASS")
        tf = sum(1 for r in t_recs if r.get("status") == "FAIL")
        te = sum(1 for r in t_recs if r.get("status") == "ERROR")
        tdur = sum(float(r.get("duration_ms", 0.0)) for r in t_recs)
        tstat = "SKIP" if sel == 0 else ("PASS" if (tf == 0 and te == 0) else ("ERROR" if te > 0 else "FAIL"))
        print(
            f"{f'Tier {t}':<8} | {sel:>8} | {tp:>6} | {tf:>6} | {te:>6} | {f'{tdur:.1f}ms':>10} | {tstat:<8}"
        )
    print("-" * len(thdr))
    all_p = sum(1 for r in records if r.get("status") == "PASS")
    all_f = sum(1 for r in records if r.get("status") == "FAIL")
    all_e = sum(1 for r in records if r.get("status") == "ERROR")
    overall = "ERROR" if (not records or all_e > 0 or not saves_ok) else ("FAIL" if all_f > 0 else "PASS")
    print(
        f"{'TOTAL':<8} | {len(records):>8} | {all_p:>6} | {all_f:>6} | {all_e:>6} | "
        f"{f'{wall_ms:.1f}ms':>10} | {overall:<8}"
    )

    # 4. Target Breakdown & Dual-Lock Isolation Footer
    print("\n=== 4. Target Breakdown & Save Isolation Footer ===")
    seen_targets = sorted({str(r.get("target", "baseline")) for r in records})
    for tg in seen_targets:
        tg_recs = [r for r in records if str(r.get("target", "baseline")) == tg]
        tgp = sum(1 for r in tg_recs if r.get("status") == "PASS")
        pct = (100.0 * tgp / len(tg_recs)) if tg_recs else 0.0
        print(f"  Target [{tg:<10}]: {tgp}/{len(tg_recs)} PASS ({pct:.1f}%)")
    print(
        f"  Formal Saves ({FORMAL_SAVES_DIR}): {'UNCHANGED (SHA-256 & mtime_ns verified)' if saves_ok else 'BREACHED!'}"
    )
    if not saves_ok:
        for d in save_diffs:
            print(f"    ! {d}")
    print(f"  Scratch Directory Hygiene: {'CLEANED' if scratch_cleaned else 'RETENTION/ERROR'}")


def execute_pipeline(cfg: RunConfig) -> int:
    """Run full discovery / quota audit / 4-stage E2E pipeline and return strict exit code."""
    t_start = time.perf_counter()
    project_dir = cfg.repo_root / "project"

    try:
        godot_bin = cfg.godot_bin if cfg.godot_bin.is_file() else resolve_godot_bin()
    except FileNotFoundError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 2

    with IsolationGuard() as guard:
        env = guard.build_subprocess_env()
        infra_errors: list[str] = []

        # Stage 0: Auto-bootstrap Godot .godot import & global_script_class_cache
        imp_ok, imp_err = ensure_godot_import_cache(
            project_dir,
            godot_bin,
            env,
            verbose=cfg.verbose,
        )
        if not imp_ok:
            print(f"[ERROR] {imp_err}", file=sys.stderr)
            return 2

        # Discover Python checks & GDScript suites
        py_checks, py_disc_errs = discover_python_checks(cfg.repo_root)
        gd_suites, gd_disc_errs = discover_gdscript_suites(cfg.repo_root)
        infra_errors.extend(py_disc_errs)
        infra_errors.extend(gd_disc_errs)

        # Stage 2a: Strict GDScript compile & warning gate (--headless -d --check-only) on core harness
        check_ok, check_errs = run_gdscript_check_only_gate(
            project_dir,
            godot_bin,
            env,
            verbose=cfg.verbose,
        )
        if not check_ok:
            infra_errors.extend(check_errs)

        if infra_errors:
            for ie in infra_errors:
                print(f"[ERROR] {ie}", file=sys.stderr)
            saves_ok, save_diffs = guard.verify_formal_saves_unchanged()
            if not saves_ok:
                for sd in save_diffs:
                    print(f"[ERROR] {sd}", file=sys.stderr)
            return 2

        # Pre-filter GDSuiteMeta suites when --tier or --feature CLI filters are active
        # (preserving full suite discovery whenever --audit-quotas is requested).
        candidate_gd_suites = (
            gd_suites
            if cfg.audit_quotas
            else [s for s in gd_suites if _suite_matches_cli_filters(s, cfg)]
        )

        # Discover GDScript case definitions via fast headless --list-only pass
        gd_case_defs: list[dict[str, Any]] = []
        if candidate_gd_suites:
            l_ok, l_defs, l_errs = _execute_gd_batch_once(
                tag="stage_list_all",
                mode="headless",
                suites=candidate_gd_suites,
                project_dir=project_dir,
                godot_bin=godot_bin,
                guard=guard,
                env=env,
                cfg=cfg,
                list_only=True,
            )
            if not l_ok:
                for le in l_errs:
                    print(f"[ERROR] GDScript case discovery failed: {le}", file=sys.stderr)
                return 2
            gd_case_defs = l_defs

        all_discovered_defs: list[dict[str, Any]] = [
            {
                "id": c["id"],
                "tier": c["tier"],
                "feature": c["feature"],
                "target": c["target"],
                "mode": c["mode"],
                "suite": c["suite"],
                "title": c["title"],
            }
            for c in py_checks
        ] + gd_case_defs

        dups = find_duplicate_ids(all_discovered_defs)
        if dups:
            for cid, suites in sorted(dups.items()):
                print(
                    f"[ERROR] Duplicate test case ID '{cid}' registered across: {suites}",
                    file=sys.stderr,
                )
            return 2

        # Handle --list and --audit-quotas modes
        if cfg.list_only or cfg.audit_quotas:
            filtered_defs = [d for d in all_discovered_defs if _case_matches_config(d, cfg)]
            quota_ok, quota_info = evaluate_quotas(
                all_discovered_defs if cfg.audit_quotas else filtered_defs
            )
            _print_discovery_tables(filtered_defs, quota_info)
            saves_ok, save_diffs = guard.verify_formal_saves_unchanged()
            cleaned = guard.cleanup()
            if not saves_ok:
                for sd in save_diffs:
                    print(f"[ERROR] {sd}", file=sys.stderr)
                return 2
            if cfg.json_out is not None:
                cfg.json_out.parent.mkdir(parents=True, exist_ok=True)
                cfg.json_out.write_text(
                    json.dumps(
                        {
                            "mode": "audit_quotas" if cfg.audit_quotas else "list",
                            "quota_summary": quota_info,
                            "cases": filtered_defs,
                            "formal_saves_unchanged": saves_ok,
                            "scratch_cleaned": cleaned,
                        },
                        indent=2,
                        ensure_ascii=False,
                    ),
                    encoding="utf-8",
                )
            if cfg.audit_quotas:
                if not quota_ok:
                    print("\n[AUDIT FAIL] Quota violations:", file=sys.stderr)
                    for v in quota_info["violations"]:
                        print(f"  - {v}", file=sys.stderr)
                    return 1
                print("\n[AUDIT PASS] All 4-tier & F1–F16 quotas satisfied (0 duplicate IDs).")
                return 0
            return 0

        # Determine which pre-filtered GDScript suites actually contain matching cases so we skip irrelevant stages
        matching_gd_suites_set = {
            str(d.get("suite", ""))
            for d in gd_case_defs
            if _case_matches_config(d, cfg)
        }
        selected_headless_suites = [
            s
            for s in candidate_gd_suites
            if s.mode == "headless" and s.rel_path in matching_gd_suites_set
        ]
        selected_visual_suites = [
            s
            for s in candidate_gd_suites
            if s.mode == "visual" and s.rel_path in matching_gd_suites_set
        ]

        all_records: list[dict[str, Any]] = []
        stage_batch_errors: list[str] = []

        # Stage 1: In-process Python checks
        py_records = run_python_checks(py_checks, cfg, guard)
        all_records.extend(py_records)

        # Stage 3: Headless GDScript suites across ALL selected tiers
        if selected_headless_suites:
            hl_records, hl_errs = run_gd_suites_with_fallback(
                stage_name="stage3_headless",
                mode="headless",
                suites=selected_headless_suites,
                project_dir=project_dir,
                godot_bin=godot_bin,
                guard=guard,
                env=env,
                cfg=cfg,
            )
            all_records.extend(hl_records)
            stage_batch_errors.extend(hl_errs)

        # Stage 4: 1920x1080 Xvfb + OpenGL3 visual GDScript suites across ALL selected tiers
        if selected_visual_suites:
            vis_records, vis_errs = run_gd_suites_with_fallback(
                stage_name="stage4_visual",
                mode="visual",
                suites=selected_visual_suites,
                project_dir=project_dir,
                godot_bin=godot_bin,
                guard=guard,
                env=env,
                cfg=cfg,
            )
            all_records.extend(vis_records)
            stage_batch_errors.extend(vis_errs)

        if cfg.keep_artifacts is not None:
            guard.preserve_artifacts(cfg.keep_artifacts)

        saves_ok, save_diffs = guard.verify_formal_saves_unchanged()
        scratch_cleaned = guard.cleanup()
        wall_ms = round((time.perf_counter() - t_start) * 1000.0, 2)

        _print_execution_report(
            all_records,
            saves_ok=saves_ok,
            save_diffs=save_diffs,
            scratch_cleaned=scratch_cleaned,
            wall_ms=wall_ms,
        )

        selected_count = len(all_records)
        passed_count = sum(1 for r in all_records if r.get("status") == "PASS")
        failed_count = sum(1 for r in all_records if r.get("status") == "FAIL")
        error_count = sum(1 for r in all_records if r.get("status") == "ERROR")

        if selected_count == 0:
            print(
                "[ERROR] Zero test cases matched the requested filters (selected_count == 0).",
                file=sys.stderr,
            )

        exit_code = 0
        if (
            selected_count == 0
            or error_count > 0
            or bool(stage_batch_errors)
            or not saves_ok
        ):
            exit_code = 2
        elif failed_count > 0 or passed_count != selected_count:
            exit_code = 1

        if cfg.json_out is not None:
            cfg.json_out.parent.mkdir(parents=True, exist_ok=True)
            report_doc = {
                "exit_code": exit_code,
                "selected_count": selected_count,
                "passed_count": passed_count,
                "failed_count": failed_count,
                "error_count": error_count,
                "duration_ms": wall_ms,
                "formal_saves_unchanged": saves_ok,
                "formal_save_diffs": save_diffs,
                "scratch_cleaned": scratch_cleaned,
                "stage_batch_errors": stage_batch_errors,
                "filters": {
                    "tiers": cfg.tiers,
                    "features": cfg.features,
                    "targets": cfg.targets,
                    "cases": cfg.cases,
                },
                "cases": all_records,
            }
            cfg.json_out.write_text(
                json.dumps(report_doc, indent=2, ensure_ascii=False),
                encoding="utf-8",
            )

        return exit_code


def parse_cli_to_config(argv: list[str], repo_root: Path) -> RunConfig:
    """Parse CLI arguments into a validated ``RunConfig`` (raises ValueError/IsolationConfigError)."""
    import argparse

    parser = argparse.ArgumentParser(
        prog="run_all_checks.py",
        description="Unified 4-Tier Opaque-Box E2E Runner for 《尘缘问道》 (chenyuan-xianxia)",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Run all 4 tiers across F1..F16 (default when --tier is omitted).",
    )
    parser.add_argument(
        "--tier",
        action="append",
        default=[],
        help="Tier filter (1..4), repeatable or comma-separated (e.g. --tier 1,2).",
    )
    parser.add_argument(
        "--feature",
        action="append",
        default=[],
        help="Feature filter (F1..F16), repeatable or comma-separated (e.g. --feature F5).",
    )
    parser.add_argument(
        "--target",
        action="append",
        default=[],
        help="Target tag filter (baseline, polish_r1..polish_r4), repeatable or comma-separated.",
    )
    parser.add_argument(
        "--case",
        action="append",
        default=[],
        help="Exact test ID filter (e.g. --case T2-F05-01), repeatable or comma-separated.",
    )
    parser.add_argument(
        "--json-out",
        type=str,
        default=None,
        help="Write structured JSON report to <path> (never /tmp).",
    )
    parser.add_argument(
        "--keep-artifacts",
        type=str,
        default=None,
        help="Preserve 1920x1080 PNG shots & batch logs into <dir> outside /tmp and repo.",
    )
    parser.add_argument(
        "--list",
        dest="list_only",
        action="store_true",
        help="List all discovered Python & GDScript test cases without running battles/Xvfb.",
    )
    parser.add_argument(
        "--audit-quotas",
        action="store_true",
        help="Verify >=184 total, >=5 T1 & >=5 T2 per F1..F16, >=16 T3, >=8 T4, and 0 duplicate IDs.",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Print raw Godot stdout/stderr logs.",
    )

    try:
        ns = parser.parse_args(argv)
    except SystemExit as sys_exit:
        # argparse exits 0 on --help and 2 on invalid flags
        raise SystemExit(int(sys_exit.code) if sys_exit.code is not None else 2)

    tiers: list[int] = []
    for raw_t in ns.tier:
        for tok in str(raw_t).split(","):
            tok = tok.strip()
            if not tok:
                continue
            if not tok.isdigit() or int(tok) not in ALL_TIERS:
                raise ValueError(f"Invalid --tier value '{tok}' (expected 1, 2, 3, or 4)")
            t_val = int(tok)
            if t_val not in tiers:
                tiers.append(t_val)
    if ns.all or not tiers:
        tiers = list(ALL_TIERS)

    features: list[str] = []
    for raw_f in ns.feature:
        for tok in str(raw_f).split(","):
            tok = tok.strip()
            if not tok:
                continue
            norm_f = normalize_feature_id(tok)
            if norm_f not in features:
                features.append(norm_f)

    targets: list[str] = []
    for raw_tg in ns.target:
        for tok in str(raw_tg).split(","):
            tok = tok.strip()
            if tok and tok not in targets:
                targets.append(tok)

    cases: list[str] = []
    for raw_c in ns.case:
        for tok in str(raw_c).split(","):
            tok = tok.strip()
            if tok and tok not in cases:
                cases.append(tok)

    json_out_path: Path | None = None
    if ns.json_out is not None:
        json_out_path = validate_output_path(
            ns.json_out,
            repo_root,
            forbid_repo_tracked=True,
            label="--json-out",
        )

    keep_artifacts_path: Path | None = None
    if ns.keep_artifacts is not None:
        keep_artifacts_path = validate_output_path(
            ns.keep_artifacts,
            repo_root,
            forbid_repo_tracked=True,
            label="--keep-artifacts",
        )

    return RunConfig(
        repo_root=repo_root,
        tiers=tiers,
        features=features,
        targets=targets,
        cases=cases,
        list_only=bool(ns.list_only),
        audit_quotas=bool(ns.audit_quotas),
        json_out=json_out_path,
        keep_artifacts=keep_artifacts_path,
        verbose=bool(ns.verbose),
    )


__all__ = [
    "GDSuiteMeta",
    "IsolationConfigError",
    "RunConfig",
    "discover_gdscript_suites",
    "discover_python_checks",
    "evaluate_quotas",
    "execute_pipeline",
    "parse_cli_to_config",
]
