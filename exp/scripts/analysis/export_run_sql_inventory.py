#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import shlex
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export per-run SQL inventory from run artifacts")
    parser.add_argument("--run-dir", required=True, help="Run directory to inspect")
    parser.add_argument(
        "--project-root",
        help="Project root containing exp/datasets/job and source scripts. Defaults to script-relative root.",
    )
    return parser.parse_args()


def script_project_root() -> Path:
    return Path(__file__).resolve().parents[3]


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def load_text(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8")


def load_env(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        if "=" not in line:
            continue
        try:
            tokens = shlex.split(line, posix=True)
        except ValueError:
            continue
        if len(tokens) != 1 or "=" not in tokens[0]:
            continue
        key, value = tokens[0].split("=", 1)
        values[key] = value
    return values


def first_non_empty(*values: Any, default: str = "") -> str:
    for value in values:
        if value is None:
            continue
        text = str(value).strip()
        if text:
            return text
    return default


def to_int(value: Any, default: int = 0) -> int:
    if value in (None, ""):
        return default
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return default


def to_float(value: Any, default: float = 0.0) -> float:
    if value in (None, ""):
        return default
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def rel_or_abs(path: Path, base: Path) -> str:
    try:
        return path.relative_to(base).as_posix()
    except ValueError:
        return path.as_posix()


def escape_md(text: str) -> str:
    return text.replace("|", "\\|")


def fence_sql(sql: str) -> str:
    body = sql.rstrip()
    if not body:
        body = "-- empty"
    return f"```sql\n{body}\n```\n"


def parse_classes_yaml(path: Path) -> dict[str, list[str]]:
    classes: dict[str, list[str]] = {}
    current: str | None = None
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.rstrip()
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if not line.startswith(" ") and stripped.endswith(":"):
            current = stripped[:-1]
            classes[current] = []
            continue
        if current and stripped.startswith("- "):
            classes[current].append(stripped[2:].strip())
    return classes


def read_source(path_text: str, fallback_root: Path) -> tuple[str, str]:
    if not path_text:
        return "", ""
    path = Path(path_text)
    if path.exists():
        return path.as_posix(), load_text(path)
    fallback = fallback_root / path_text
    if fallback.exists():
        return fallback.as_posix(), load_text(fallback)
    return path_text, ""


def wait_xact_sql_block(target_movie_id: str, lock_hold_seconds: int) -> dict[str, str]:
    blocker = f"""BEGIN;
SELECT movie_id FROM movie_freshness WHERE movie_id = {target_movie_id} FOR UPDATE;
SELECT pg_sleep({lock_hold_seconds});
COMMIT;"""
    waiter = f"""UPDATE movie_freshness
SET epoch = epoch + 1,
    hot_flag = true,
    freshness_score = freshness_score + 1,
    last_touch_ts = now()
WHERE movie_id = {target_movie_id};"""
    return {"blocker_sql": blocker, "waiter_sql": waiter}


def deadlock_sql_block(row_a: str, row_b: str, timeout_ms: int = 3000) -> dict[str, str]:
    session_a = f"""\\set VERBOSITY verbose
SET deadlock_timeout = '{timeout_ms}ms';
BEGIN;
UPDATE movie_freshness
SET epoch = epoch + 1,
    hot_flag = true,
    freshness_score = freshness_score + 1,
    last_touch_ts = now()
WHERE movie_id = {row_a};
SELECT pg_sleep(1);
UPDATE movie_freshness
SET epoch = epoch + 1,
    hot_flag = true,
    freshness_score = freshness_score + 1,
    last_touch_ts = now()
WHERE movie_id = {row_b};
COMMIT;"""
    session_b = f"""\\set VERBOSITY verbose
SET deadlock_timeout = '{timeout_ms}ms';
BEGIN;
UPDATE movie_freshness
SET epoch = epoch + 1,
    hot_flag = true,
    freshness_score = freshness_score + 1,
    last_touch_ts = now()
WHERE movie_id = {row_b};
SELECT pg_sleep(1);
UPDATE movie_freshness
SET epoch = epoch + 1,
    hot_flag = true,
    freshness_score = freshness_score + 1,
    last_touch_ts = now()
WHERE movie_id = {row_a};
COMMIT;"""
    return {"session_a_sql": session_a, "session_b_sql": session_b}


def spill_sql_block(session_memory: str, ap_sql: str) -> str:
    return f"SET work_mem = '{session_memory}';\n{ap_sql.rstrip()}"


def collect_tp_section(run_dir: Path) -> dict[str, Any]:
    derived_dir = run_dir / "derived"
    tp_profile_env = load_env(derived_dir / "tp-profile.env")
    tp_profile = load_json(derived_dir / "tp-profile.json")
    sql_path = derived_dir / "tp-template-resolved.sql"
    return {
        "driver": first_non_empty(tp_profile_env.get("JOB_TP_DRIVER"), tp_profile.get("driver"), default="unknown"),
        "template_id": tp_profile_env.get("JOB_TP_TEMPLATE_ID", ""),
        "threads": to_int(tp_profile_env.get("JOB_TP_THREADS")),
        "terminals": to_int(tp_profile_env.get("JOB_TP_TERMINALS")),
        "rate_cap": to_int(tp_profile_env.get("JOB_TP_RATE_CAP")),
        "batch_size": to_int(tp_profile_env.get("JOB_TP_BATCH_SIZE")),
        "hot_modulus": to_int(tp_profile_env.get("JOB_TP_HOT_MODULUS")),
        "hot_remainder": to_int(tp_profile_env.get("JOB_TP_HOT_REMAINDER")),
        "materialized_path": sql_path.as_posix(),
        "materialized_path_relative": rel_or_abs(sql_path, run_dir),
        "sql": load_text(sql_path),
    }


def collect_ap_section(run_dir: Path, project_root: Path) -> dict[str, Any]:
    derived_dir = run_dir / "derived"
    mixed_baseline = load_json(derived_dir / "mixed-baseline.json")
    ap_baseline = load_json(derived_dir / "ap-baseline.json")
    tp_profile_env = load_env(derived_dir / "tp-profile.env")
    classes_yaml = project_root / "exp" / "datasets" / "job" / "queries" / "classes.yaml"
    class_pools = parse_classes_yaml(classes_yaml) if classes_yaml.exists() else {}

    ap_class = first_non_empty(
        mixed_baseline.get("ap_class"),
        ap_baseline.get("ap_class"),
        tp_profile_env.get("AP_CLASS"),
        default="na",
    )
    drift_sample = derived_dir / "query-drift-sample.sql"
    if drift_sample.exists():
        actual_path = drift_sample.as_posix()
        actual_sql = load_text(drift_sample)
        source_kind = "drift-sample"
    else:
        actual_path, actual_sql = read_source(
            first_non_empty(mixed_baseline.get("ap_query_file"), ap_baseline.get("query_file"), default=""),
            project_root,
        )
        source_kind = "fixed-ap-file"
    return {
        "ap_class": ap_class,
        "source_kind": source_kind,
        "actual_sql_path": actual_path,
        "actual_sql_path_relative": rel_or_abs(Path(actual_path), run_dir) if actual_path.startswith(run_dir.as_posix()) else actual_path,
        "actual_sql": actual_sql,
        "class_pool": class_pools.get(ap_class, []),
        "class_pool_source": rel_or_abs(classes_yaml, project_root) if classes_yaml.exists() else "",
        "terminals": to_int(first_non_empty(mixed_baseline.get("ap_terminals"), ap_baseline.get("terminals"), tp_profile_env.get("AP_TERMINALS"), default="0")),
        "parallelism": to_int(tp_profile_env.get("AP_PARALLELISM")),
        "burst_interval_seconds": to_int(first_non_empty(mixed_baseline.get("burst_interval_seconds"), ap_baseline.get("burst_interval_seconds"), tp_profile_env.get("AP_BURST_INTERVAL_SECONDS"), default="0")),
        "rounds_completed": to_int(first_non_empty(mixed_baseline.get("ap_rounds_completed"), ap_baseline.get("rounds_completed"), default="0")),
    }


def collect_probe_sections(run_dir: Path) -> list[dict[str, Any]]:
    derived_dir = run_dir / "derived"
    sections: list[dict[str, Any]] = []
    freshness_sql = derived_dir / "freshness-probe.sql"
    if freshness_sql.exists():
        profile = load_json(derived_dir / "freshness-profile.json")
        sections.append(
            {
                "kind": "query-oriented-freshness",
                "probe_id": profile.get("ProbeID") or profile.get("probe_id", ""),
                "query_class": profile.get("QueryClass") or profile.get("query_class", ""),
                "target_range": profile.get("TargetRange") or profile.get("target_range", ""),
                "source_path": profile.get("ProbeSource") or profile.get("probe_source", ""),
                "materialized_path": freshness_sql.as_posix(),
                "materialized_path_relative": rel_or_abs(freshness_sql, run_dir),
                "sql": load_text(freshness_sql),
            }
        )
    sync_sql = derived_dir / "sync-latency-probe.sql"
    if sync_sql.exists():
        profile = load_json(derived_dir / "sync-latency-profile.json")
        sections.append(
            {
                "kind": "sync-latency",
                "probe_id": profile.get("ProbeID") or profile.get("probe_id", ""),
                "query_class": profile.get("QueryClass") or profile.get("query_class", ""),
                "target_range": profile.get("TargetRange") or profile.get("target_range", ""),
                "poll_interval_ms": to_int(profile.get("PollIntervalMs") or profile.get("poll_interval_ms")),
                "timeout_ms": to_int(profile.get("TimeoutMs") or profile.get("timeout_ms")),
                "source_path": profile.get("ProbeSource") or profile.get("probe_source", ""),
                "materialized_path": sync_sql.as_posix(),
                "materialized_path_relative": rel_or_abs(sync_sql, run_dir),
                "sql": load_text(sync_sql),
            }
        )
    return sections


def collect_single_chaos_sections(run_dir: Path, ap_section: dict[str, Any]) -> list[dict[str, Any]]:
    derived_dir = run_dir / "derived"
    sections: list[dict[str, Any]] = []

    waitxact = load_json(derived_dir / "waitxact-chaos.json")
    if waitxact:
        target_movie_id = str(waitxact.get("target_movie_id", "")).strip()
        lock_hold_seconds = to_int(waitxact.get("lock_hold_seconds"), 15)
        sql_parts = wait_xact_sql_block(target_movie_id, lock_hold_seconds) if target_movie_id else {"blocker_sql": "", "waiter_sql": ""}
        sections.append(
            {
                "primitive": "wait_xact",
                "status": waitxact.get("status", ""),
                "intensity": waitxact.get("intensity", ""),
                "target_selector": waitxact.get("target_selector", ""),
                "target_movie_id": target_movie_id,
                "jobs": to_int(waitxact.get("waiter_jobs")),
                "lock_hold_seconds": lock_hold_seconds,
                "duration_seconds": to_int(waitxact.get("duration_seconds")),
                "actual_sql": sql_parts,
            }
        )

    deadlock = load_json(derived_dir / "deadlock-pair-chaos.json")
    if deadlock:
        row_a = str(deadlock.get("row_a_movie_id", "")).strip()
        row_b = str(deadlock.get("row_b_movie_id", "")).strip()
        sql_parts = deadlock_sql_block(row_a, row_b) if row_a and row_b else {"session_a_sql": "", "session_b_sql": ""}
        sections.append(
            {
                "primitive": "deadlock_pair",
                "status": deadlock.get("status", ""),
                "intensity": deadlock.get("intensity", ""),
                "target_selector": deadlock.get("target_selector", ""),
                "row_a_movie_id": row_a,
                "row_b_movie_id": row_b,
                "jobs": to_int(deadlock.get("deadlock_jobs")),
                "duration_seconds": to_int(deadlock.get("duration_seconds")),
                "actual_sql": sql_parts,
            }
        )

    spill = load_json(derived_dir / "spill-pressure-chaos.json")
    if spill:
        ap_sql = ""
        ap_sql_path = spill.get("ap_query_file", "")
        if ap_sql_path:
            ap_sql = load_text(Path(ap_sql_path)) if Path(ap_sql_path).exists() else ""
        if not ap_sql:
            ap_sql = ap_section.get("actual_sql", "")
        session_memory = first_non_empty(spill.get("session_memory"), default="64kB")
        sections.append(
            {
                "primitive": "spill_pressure",
                "status": spill.get("status", ""),
                "intensity": spill.get("intensity", ""),
                "target_selector": spill.get("target_selector", ""),
                "ap_query_class": spill.get("ap_query_class", ap_section.get("ap_class", "")),
                "ap_query_file": ap_sql_path,
                "workers": to_int(spill.get("workers")),
                "session_memory": session_memory,
                "requested_rate_qps": to_float(spill.get("requested_rate_qps")),
                "actual_rate_qps": to_float(spill.get("actual_rate_qps")),
                "actual_sql": {"worker_sql": spill_sql_block(session_memory, ap_sql) if ap_sql else ""},
            }
        )

    return sections


def collect_multi_fault_sections(run_dir: Path, single_sections: list[dict[str, Any]]) -> list[dict[str, Any]]:
    manifest_env = load_env(run_dir / "manifest.env")
    raw_ids = manifest_env.get("CHAOS_INJECTION_IDS", "")
    if not raw_ids:
        return []
    by_primitive: dict[str, list[dict[str, Any]]] = {}
    for section in single_sections:
        by_primitive.setdefault(section.get("primitive", ""), []).append(section)

    sections: list[dict[str, Any]] = []
    for idx, injection_id in enumerate(raw_ids.split("|"), start=1):
        injection_id = injection_id.strip()
        if not injection_id:
            continue
        primitive = manifest_env.get(f"CHAOS_INJECTION_{idx}_PRIMITIVE", "")
        stage = manifest_env.get(f"CHAOS_INJECTION_{idx}_STAGE", "")
        target_selector = manifest_env.get(f"CHAOS_INJECTION_{idx}_TARGET_SELECTOR", "")
        intensity = manifest_env.get(f"CHAOS_INJECTION_{idx}_INTENSITY", "")
        start_after_seconds = to_int(manifest_env.get(f"CHAOS_INJECTION_{idx}_START_AFTER_SECONDS"))
        duration_seconds = to_int(manifest_env.get(f"CHAOS_INJECTION_{idx}_DURATION_SECONDS"))
        matched = by_primitive.get(primitive, [])
        actual_section = matched.pop(0) if matched else {}
        sections.append(
            {
                "injection_id": injection_id,
                "primitive": primitive,
                "stage": stage,
                "target_selector": target_selector,
                "intensity": intensity,
                "start_after_seconds": start_after_seconds,
                "duration_seconds": duration_seconds,
                "jobs": to_int(manifest_env.get(f"CHAOS_INJECTION_{idx}_JOBS")),
                "lock_hold_seconds": to_int(manifest_env.get(f"CHAOS_INJECTION_{idx}_LOCK_HOLD_SECONDS")),
                "fixture": manifest_env.get(f"CHAOS_INJECTION_{idx}_FIXTURE", ""),
                "workers": to_int(manifest_env.get(f"CHAOS_INJECTION_{idx}_WORKERS")),
                "session_memory": manifest_env.get(f"CHAOS_INJECTION_{idx}_SESSION_MEMORY", ""),
                "rate": to_float(manifest_env.get(f"CHAOS_INJECTION_{idx}_RATE")),
                "spill_query_class": manifest_env.get(f"CHAOS_INJECTION_{idx}_SPILL_QUERY_CLASS", ""),
                "status": actual_section.get("status", ""),
                "actual_sql": actual_section.get("actual_sql", {}),
                "actual_target_movie_id": actual_section.get("target_movie_id", ""),
                "actual_row_a_movie_id": actual_section.get("row_a_movie_id", ""),
                "actual_row_b_movie_id": actual_section.get("row_b_movie_id", ""),
            }
        )
    return sections


def build_inventory(run_dir: Path, project_root: Path) -> dict[str, Any]:
    summary = load_json(run_dir / "summary.json")
    mixed_baseline = load_json(run_dir / "derived" / "mixed-baseline.json")
    tp_section = collect_tp_section(run_dir)
    ap_section = collect_ap_section(run_dir, project_root)
    probe_sections = collect_probe_sections(run_dir)
    single_chaos_sections = collect_single_chaos_sections(run_dir, ap_section)
    multi_fault_sections = collect_multi_fault_sections(run_dir, single_chaos_sections)
    manifest_env = load_env(run_dir / "manifest.env")
    report_props = load_env(run_dir / "report" / "run.properties.effective")

    return {
        "run_dir": run_dir.as_posix(),
        "run_name": summary.get("run_name", ""),
        "run_id": summary.get("run_id", ""),
        "rq": summary.get("rq", ""),
        "system": summary.get("system", ""),
        "dataset": summary.get("dataset", ""),
        "budget_tier": summary.get("budget_tier", ""),
        "tp_pressure": summary.get("tp_pressure", ""),
        "overlap": summary.get("overlap", ""),
        "variant": summary.get("variant", ""),
        "ap_class": ap_section.get("ap_class", "na"),
        "chaos_mode": first_non_empty(report_props.get("chaos_mode"), manifest_env.get("CHAOS_MODE"), mixed_baseline.get("chaos_mode"), default="none"),
        "htap_check_type": first_non_empty(report_props.get("htap_check_type"), manifest_env.get("HTAP_CHECK_TYPE"), mixed_baseline.get("htap_check_type"), default="none"),
        "workload_drift_enabled": (run_dir / "derived" / "query-drift-sample.sql").exists(),
        "tp": tp_section,
        "ap": ap_section,
        "htap_checks": probe_sections,
        "chaos": single_chaos_sections,
        "multi_fault": multi_fault_sections,
        "paths": {
            "manifest_env": (run_dir / "manifest.env").as_posix(),
            "manifest_resolved": (run_dir / "manifest.resolved.txt").as_posix(),
            "sql_asset_json": (run_dir / "derived" / "workload-sql-set.json").as_posix(),
            "sql_asset_md": (run_dir / "derived" / "workload-sql-set.md").as_posix(),
        },
    }


def render_probe_md(section: dict[str, Any]) -> str:
    lines = [
        f"### {section.get('kind', 'probe')}",
        f"- probe_id: `{section.get('probe_id', '')}`",
        f"- query_class: `{section.get('query_class', '')}`",
        f"- target_range: `{section.get('target_range', '')}`",
    ]
    if section.get("poll_interval_ms"):
        lines.append(f"- poll_interval_ms: `{section.get('poll_interval_ms')}`")
    if section.get("timeout_ms"):
        lines.append(f"- timeout_ms: `{section.get('timeout_ms')}`")
    if section.get("source_path"):
        lines.append(f"- source_path: `{section.get('source_path')}`")
    lines.append(f"- materialized_path: `{section.get('materialized_path_relative', section.get('materialized_path', ''))}`")
    lines.append("")
    lines.append(fence_sql(section.get("sql", "")))
    return "\n".join(lines)


def render_chaos_md(section: dict[str, Any]) -> str:
    lines = [
        f"### {section.get('primitive', 'chaos')}",
        f"- status: `{section.get('status', '')}`",
        f"- intensity: `{section.get('intensity', '')}`",
        f"- target_selector: `{section.get('target_selector', '')}`",
    ]
    if section.get("target_movie_id"):
        lines.append(f"- target_movie_id: `{section.get('target_movie_id')}`")
    if section.get("row_a_movie_id"):
        lines.append(f"- row_a_movie_id: `{section.get('row_a_movie_id')}`")
    if section.get("row_b_movie_id"):
        lines.append(f"- row_b_movie_id: `{section.get('row_b_movie_id')}`")
    if section.get("jobs"):
        lines.append(f"- jobs: `{section.get('jobs')}`")
    if section.get("lock_hold_seconds"):
        lines.append(f"- lock_hold_seconds: `{section.get('lock_hold_seconds')}`")
    if section.get("workers"):
        lines.append(f"- workers: `{section.get('workers')}`")
    if section.get("session_memory"):
        lines.append(f"- session_memory: `{section.get('session_memory')}`")
    if section.get("requested_rate_qps"):
        lines.append(f"- requested_rate_qps: `{section.get('requested_rate_qps')}`")
    if section.get("actual_rate_qps"):
        lines.append(f"- actual_rate_qps: `{section.get('actual_rate_qps')}`")
    lines.append("")
    actual_sql = section.get("actual_sql", {})
    if isinstance(actual_sql, dict):
        for label, sql in actual_sql.items():
            lines.append(f"#### {label}")
            lines.append("")
            lines.append(fence_sql(str(sql)))
    else:
        lines.append(fence_sql(str(actual_sql)))
    return "\n".join(lines)


def render_multi_fault_md(sections: list[dict[str, Any]]) -> str:
    lines = ["## multi-fault injection order", ""]
    for section in sections:
        lines.extend(
            [
                f"### {section.get('injection_id', '')} / {section.get('primitive', '')}",
                f"- stage: `{section.get('stage', '')}`",
                f"- intensity: `{section.get('intensity', '')}`",
                f"- target_selector: `{section.get('target_selector', '')}`",
                f"- start_after_seconds: `{section.get('start_after_seconds', 0)}`",
                f"- duration_seconds: `{section.get('duration_seconds', 0)}`",
            ]
        )
        if section.get("jobs"):
            lines.append(f"- jobs: `{section.get('jobs')}`")
        if section.get("lock_hold_seconds"):
            lines.append(f"- lock_hold_seconds: `{section.get('lock_hold_seconds')}`")
        if section.get("fixture"):
            lines.append(f"- fixture: `{section.get('fixture')}`")
        if section.get("workers"):
            lines.append(f"- workers: `{section.get('workers')}`")
        if section.get("session_memory"):
            lines.append(f"- session_memory: `{section.get('session_memory')}`")
        if section.get("rate"):
            lines.append(f"- rate: `{section.get('rate')}`")
        if section.get("spill_query_class"):
            lines.append(f"- spill_query_class: `{section.get('spill_query_class')}`")
        if section.get("actual_target_movie_id"):
            lines.append(f"- actual_target_movie_id: `{section.get('actual_target_movie_id')}`")
        if section.get("actual_row_a_movie_id"):
            lines.append(f"- actual_row_a_movie_id: `{section.get('actual_row_a_movie_id')}`")
        if section.get("actual_row_b_movie_id"):
            lines.append(f"- actual_row_b_movie_id: `{section.get('actual_row_b_movie_id')}`")
        lines.append("")
        actual_sql = section.get("actual_sql", {})
        if isinstance(actual_sql, dict):
            for label, sql in actual_sql.items():
                lines.append(f"#### {label}")
                lines.append("")
                lines.append(fence_sql(str(sql)))
        else:
            lines.append(fence_sql(str(actual_sql)))
    return "\n".join(lines)


def render_markdown(inventory: dict[str, Any]) -> str:
    tp = inventory["tp"]
    ap = inventory["ap"]
    lines = [
        f"# workload sql set — {inventory.get('run_name', '')}",
        "",
        "## run identity",
        "",
        f"- run_id: `{inventory.get('run_id', '')}`",
        f"- rq: `{inventory.get('rq', '')}`",
        f"- system: `{inventory.get('system', '')}`",
        f"- dataset: `{inventory.get('dataset', '')}`",
        f"- budget_tier: `{inventory.get('budget_tier', '')}`",
        f"- tp_pressure: `{inventory.get('tp_pressure', '')}`",
        f"- overlap: `{inventory.get('overlap', '')}`",
        f"- variant: `{inventory.get('variant', '')}`",
        f"- chaos_mode: `{inventory.get('chaos_mode', '')}`",
        f"- htap_check_type: `{inventory.get('htap_check_type', '')}`",
        "",
        "## tp sql",
        "",
        f"- driver: `{tp.get('driver', '')}`",
        f"- template_id: `{tp.get('template_id', '')}`",
        f"- threads: `{tp.get('threads', 0)}`",
        f"- terminals: `{tp.get('terminals', 0)}`",
        f"- batch_size: `{tp.get('batch_size', 0)}`",
        f"- hot_range: `movie_id % {tp.get('hot_modulus', 0)} = {tp.get('hot_remainder', 0)}`",
        f"- materialized_path: `{tp.get('materialized_path_relative', '')}`",
        "",
        fence_sql(tp.get("sql", "")),
        "## ap sql",
        "",
        f"- ap_class: `{ap.get('ap_class', '')}`",
        f"- source_kind: `{ap.get('source_kind', '')}`",
        f"- actual_sql_path: `{ap.get('actual_sql_path_relative', ap.get('actual_sql_path', ''))}`",
        f"- terminals: `{ap.get('terminals', 0)}`",
        f"- parallelism: `{ap.get('parallelism', 0)}`",
        f"- burst_interval_seconds: `{ap.get('burst_interval_seconds', 0)}`",
        f"- rounds_completed: `{ap.get('rounds_completed', 0)}`",
        "",
        fence_sql(ap.get("actual_sql", "")),
        "### class pool",
        "",
    ]
    if ap.get("class_pool"):
        for entry in ap["class_pool"]:
            lines.append(f"- `{entry}`")
    else:
        lines.append("- _not available_")
    lines.extend(["", f"- class_pool_source: `{ap.get('class_pool_source', '')}`", ""])

    if inventory["htap_checks"]:
        lines.append("## htap probe sql")
        lines.append("")
        for section in inventory["htap_checks"]:
            lines.append(render_probe_md(section))
            lines.append("")

    if inventory["chaos"]:
        lines.append("## chaos sql")
        lines.append("")
        for section in inventory["chaos"]:
            lines.append(render_chaos_md(section))
            lines.append("")

    if inventory["multi_fault"]:
        lines.append(render_multi_fault_md(inventory["multi_fault"]))
        lines.append("")

    lines.extend(
        [
            "## asset paths",
            "",
            f"- manifest_env: `{inventory['paths']['manifest_env']}`",
            f"- manifest_resolved: `{inventory['paths']['manifest_resolved']}`",
            f"- sql_asset_json: `{inventory['paths']['sql_asset_json']}`",
            f"- sql_asset_md: `{inventory['paths']['sql_asset_md']}`",
            "",
        ]
    )
    return "\n".join(lines).rstrip() + "\n"


def main() -> None:
    args = parse_args()
    run_dir = Path(args.run_dir).expanduser().resolve()
    project_root = Path(args.project_root).expanduser().resolve() if args.project_root else script_project_root()
    derived_dir = run_dir / "derived"
    derived_dir.mkdir(parents=True, exist_ok=True)

    inventory = build_inventory(run_dir, project_root)
    json_path = derived_dir / "workload-sql-set.json"
    md_path = derived_dir / "workload-sql-set.md"
    json_path.write_text(json.dumps(inventory, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    md_path.write_text(render_markdown(inventory), encoding="utf-8")


if __name__ == "__main__":
    main()
