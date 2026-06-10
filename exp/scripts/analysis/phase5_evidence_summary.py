#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import re
import shlex
from collections import defaultdict
from pathlib import Path
from statistics import mean, pstdev
from typing import Any

NUMERIC_METRICS = [
    "tp_tps",
    "tp_latency_avg_ms",
    "tp_transactions",
    "ap_rounds_completed",
    "ap_parallelism",
    "report_bundle_missing_count",
    "recovery_time_ms",
    "freshness_samples",
    "freshness_max_epoch_delta",
    "freshness_latest_lag_ms",
    "sync_samples",
    "sync_max_ms",
    "sync_post_ms",
    "workload_drift_realized_factor",
    "data_drift_factor",
    "wait_duration_ms",
    "deadlock_detected_count",
    "deadlock_abort_count",
    "spill_temp_files_delta",
    "spill_temp_bytes_delta",
    "spill_execution_rate_qps",
    "sql_asset_present",
]

SEED_GROUP_FIELDS = [
    "rq",
    "system",
    "memory_profile",
    "cgroup_cpu_limit",
    "cgroup_memory_limit",
    "postgres_image",
    "dataset",
    "budget_tier",
    "tp_pressure",
    "ap_class",
    "ap_parallelism",
    "cleanup_profile",
    "safety_level",
    "feature_scope",
    "data_drift_factor",
    "overlap",
    "variant",
    "baseline_kind",
    "chaos_mode",
    "chaos_primitive",
    "htap_check_type",
    "workload_drift_factor",
    "workload_drift_sample_size",
    "workload_drift_base_class",
]

COMPARISON_GROUP_FIELDS = [
    "rq",
    "memory_profile",
    "cgroup_cpu_limit",
    "cgroup_memory_limit",
    "postgres_image",
    "dataset",
    "budget_tier",
    "tp_pressure",
    "ap_class",
    "ap_parallelism",
    "cleanup_profile",
    "safety_level",
    "feature_scope",
    "data_drift_factor",
    "overlap",
    "chaos_mode",
    "chaos_primitive",
    "htap_check_type",
    "workload_drift_factor",
    "workload_drift_sample_size",
    "workload_drift_base_class",
]

FAMILY_GROUP_FIELDS = [
    "memory_profile",
    "cgroup_cpu_limit",
    "cgroup_memory_limit",
    "postgres_image",
    "tier_group",
    "figure_group",
    "figure_group_title",
    "figure_group_slot",
    "family_group",
    "family_member",
]

FIGURE_GROUPS: dict[str, dict[str, Any]] = {
    "G1": {
        "title": "Single-fault intensity curves",
        "slot": "Main Fig. G1",
        "comparison": "wait_xact / spill_pressure / deadlock_pair across L1-L3",
        "metrics": [
            "tp_tps",
            "tp_latency_avg_ms",
            "wait_duration_ms",
            "deadlock_detected_count",
            "spill_temp_bytes_delta",
        ],
    },
    "G2": {
        "title": "HTAP-check and drift observation",
        "slot": "Main Fig. G2",
        "comparison": "query freshness / sync latency / workload drift across L1-L3",
        "metrics": [
            "tp_tps",
            "tp_latency_avg_ms",
            "freshness_latest_lag_ms",
            "sync_post_ms",
            "workload_drift_realized_factor",
        ],
    },
    "G3": {
        "title": "Multi-chaos stacking",
        "slot": "Main Fig. G3",
        "comparison": "wait_xact+spill / spill+drift / wait_xact+deadlock / multifault",
        "metrics": [
            "tp_tps",
            "tp_latency_avg_ms",
            "wait_duration_ms",
            "deadlock_detected_count",
            "spill_temp_bytes_delta",
            "workload_drift_realized_factor",
        ],
    },
    "G4": {
        "title": "TP pressure sensitivity",
        "slot": "Main Fig. G4",
        "comparison": "low / medium / high TP pressure anchored on the Tier 2 variants",
        "metrics": [
            "tp_tps",
            "tp_latency_avg_ms",
            "spill_temp_bytes_delta",
            "wait_duration_ms",
            "deadlock_detected_count",
        ],
    },
    "G5": {
        "title": "Long-duration recovery",
        "slot": "Main Fig. G5",
        "comparison": "spill / wait_xact / multifault / heavy drift with long observation windows",
        "metrics": [
            "tp_tps",
            "tp_latency_avg_ms",
            "recovery_time_ms",
            "wait_duration_ms",
            "spill_temp_bytes_delta",
            "sync_post_ms",
            "workload_drift_realized_factor",
        ],
    },
}

TIER_ORDER = {"tier0": 0, "tier1": 1, "tier2": 2, "tier3": 3}
FIGURE_ORDER = {key: idx for idx, key in enumerate(FIGURE_GROUPS.keys(), start=1)}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Summarize the mixed-workload matrix across multiple run dirs"
    )
    parser.add_argument("--output-dir", required=True, help="Directory to write summary CSV/MD files")
    parser.add_argument(
        "--run-dir",
        action="append",
        default=[],
        help="Add a run directory to summarize. Can be repeated.",
    )
    parser.add_argument(
        "--runlist",
        type=Path,
        help="Text file with one run directory per line (blank lines and comments are ignored)",
    )
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


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


def rel_or_abs(path: Path, base: Path) -> str:
    try:
        return path.relative_to(base).as_posix()
    except ValueError:
        return path.as_posix()


def to_int(value: Any, default: int | None = None) -> int | None:
    if value is None or value == "":
        return default
    if isinstance(value, bool):
        return int(value)
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return default


def to_float(value: Any, default: float | None = None) -> float | None:
    if value is None or value == "":
        return default
    if isinstance(value, bool):
        return float(value)
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def to_bool(value: Any, default: bool = False) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    text = str(value).strip().lower()
    if text in {"1", "true", "yes", "on"}:
        return True
    if text in {"0", "false", "no", "off"}:
        return False
    return default


def first_non_empty(*values: Any, default: str = "") -> str:
    for value in values:
        if value is None:
            continue
        text = str(value).strip()
        if text:
            return text
    return default


def normalize_float(value: Any) -> float | None:
    parsed = to_float(value)
    if parsed is None:
        return None
    return parsed


def format_number(value: Any, digits: int = 6) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        text = f"{value:.{digits}f}".rstrip("0").rstrip(".")
        return text if text else "0"
    return str(value)


def format_list(values: list[Any]) -> str:
    if not values:
        return ""
    return "|".join(str(value) for value in values)


def markdown_escape(text: Any) -> str:
    return str(text).replace("|", "\\|")


def rows_to_markdown(rows: list[dict[str, Any]], columns: list[str]) -> str:
    if not rows:
        return "_No rows._\n"
    lines = ["| " + " | ".join(columns) + " |", "| " + " | ".join("---" for _ in columns) + " |"]
    for row in rows:
        lines.append("| " + " | ".join(markdown_escape(row.get(column, "")) for column in columns) + " |")
    return "\n".join(lines) + "\n"


def stringify_row(row: dict[str, Any], columns: list[str]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for column in columns:
        value = row.get(column, "")
        if isinstance(value, (int, float, bool)) or value is None:
            out[column] = format_number(value)
        else:
            out[column] = value
    return out


def resolve_run_dirs(args: argparse.Namespace) -> list[Path]:
    run_dirs: list[Path] = []
    seen: set[Path] = set()

    def add_run_dir(raw_value: str | Path) -> None:
        path = Path(raw_value).expanduser()
        try:
            resolved = path.resolve(strict=False)
        except OSError:
            resolved = path
        if resolved in seen:
            return
        seen.add(resolved)
        run_dirs.append(resolved)

    for raw in args.run_dir:
        add_run_dir(raw)

    if args.runlist:
        for raw_line in args.runlist.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            add_run_dir(line)

    return run_dirs


def derive_baseline_kind(run_dir: Path) -> str:
    if (run_dir / "derived" / "mixed-baseline.json").exists():
        return "mixed"
    if (run_dir / "derived" / "ap-baseline.json").exists():
        return "ap-only"
    if (run_dir / "derived" / "tp-baseline.json").exists():
        return "tp-only"
    if (run_dir / "derived" / "generator").exists():
        return "generator"
    return "unknown"


def parse_tp_metrics(log_path: Path) -> dict[str, float | int | str]:
    summary_path = log_path.parent / "summary.json"
    summary = load_json(summary_path)
    if summary:
        result: dict[str, float | int | str] = {
            "driver": str(summary.get("driver", "")).strip() or "pgbench",
        }
        if summary.get("tp_tps") not in (None, ""):
            result["tp_tps"] = float(summary["tp_tps"])
        if summary.get("tp_latency_avg_ms") not in (None, ""):
            result["tp_latency_avg_ms"] = float(summary["tp_latency_avg_ms"])
        if summary.get("tp_transactions") not in (None, ""):
            result["tp_transactions"] = int(summary["tp_transactions"])
        return result
    if not log_path.exists():
        return {}
    text = log_path.read_text(encoding="utf-8", errors="replace")
    result: dict[str, float | int | str] = {"driver": "pgbench"}
    tps_matches = re.findall(r"tps = ([0-9.]+)", text)
    if tps_matches:
        result["tp_tps"] = float(tps_matches[-1])
    latency_matches = re.findall(r"latency average = ([0-9.]+) ms", text)
    if latency_matches:
        result["tp_latency_avg_ms"] = float(latency_matches[-1])
    txn_matches = re.findall(r"number of transactions actually processed: ([0-9]+)", text)
    if txn_matches:
        result["tp_transactions"] = int(txn_matches[-1])
    return result


def mean_std(values: list[float | int]) -> tuple[float | None, float | None]:
    if not values:
        return None, None
    if len(values) == 1:
        value = float(values[0])
        return value, 0.0
    float_values = [float(value) for value in values]
    return mean(float_values), pstdev(float_values)


def normalize_label(*values: Any) -> str:
    return " ".join(str(value).strip().lower() for value in values if str(value).strip())


def infer_tier_group(variant: str, run_name: str, run_id: str) -> str:
    text = normalize_label(variant, run_name, run_id)
    if "-long" in text or "workload-drift-heavy-long" in text:
        return "tier3"
    if "lowtp" in text or "hightp" in text:
        return "tier2"
    if any(token in text for token in ("waitxact-spill", "spill-drift", "waitxact-deadlock")):
        return "tier1"
    if "multifault-l2" in text and "hightp" not in text and "-long" not in text:
        return "tier1"
    return "tier0"


def infer_figure_group(tier_group: str, variant: str, htap_check_type: str) -> str:
    variant_text = normalize_label(variant)
    htap_text = normalize_label(htap_check_type)
    if tier_group == "tier3":
        return "G5"
    if tier_group == "tier2":
        return "G4"
    if tier_group == "tier1":
        return "G3"
    if any(token in variant_text for token in ("freshness", "synclatency", "drift")):
        return "G2"
    if htap_text not in {"", "none", "not-requested"}:
        return "G2"
    return "G1"


def infer_family_group(figure_group: str) -> str:
    return {
        "G1": "single-fault-intensity",
        "G2": "htap-drift-observation",
        "G3": "multi-chaos-stacking",
        "G4": "tp-pressure-sensitivity",
        "G5": "long-duration-recovery",
    }.get(figure_group, "matrix-other")


def infer_family_member(figure_group: str, variant: str, chaos_primitive: str, htap_check_type: str) -> str:
    variant_text = normalize_label(variant)
    chaos_text = normalize_label(chaos_primitive)
    htap_text = normalize_label(htap_check_type)

    if figure_group == "G1":
        if "waitxact" in variant_text or chaos_text == "wait_xact":
            return "wait_xact"
        if "spill" in variant_text or chaos_text == "spill_pressure":
            return "spill_pressure"
        if "deadlock" in variant_text or chaos_text == "deadlock_pair":
            return "deadlock_pair"
    if figure_group == "G2":
        if "freshness" in variant_text or htap_text == "query-oriented":
            return "query_freshness"
        if "synclatency" in variant_text or htap_text == "sync-latency":
            return "sync_latency"
        if "drift" in variant_text:
            return "workload_drift"
    if figure_group == "G3":
        if "waitxact-spill" in variant_text:
            return "wait_xact+spill_pressure"
        if "spill-drift" in variant_text:
            return "spill_pressure+workload_drift"
        if "waitxact-deadlock" in variant_text:
            return "wait_xact+deadlock_pair"
        if "multifault" in variant_text:
            return "wait_xact+spill_pressure+deadlock_pair"
    if figure_group == "G4":
        if "spill-l2-lowtp" in variant_text:
            return "spill_pressure@low_tp"
        if "spill-l2-hightp" in variant_text:
            return "spill_pressure@high_tp"
        if "multifault-l2-hightp" in variant_text:
            return "multifault@high_tp"
    if figure_group == "G5":
        if "spill-l3-long" in variant_text:
            return "spill_pressure_long"
        if "waitxact-l3-long" in variant_text:
            return "wait_xact_long"
        if "multifault-l2-long" in variant_text:
            return "multifault_long"
        if "drift-heavy-long" in variant_text or "workload-drift-heavy-long" in variant_text:
            return "workload_drift_long"
    return variant or "unknown"


def build_workload_signature(
    ap_class: str,
    ap_sql_source_kind: str,
    htap_check_type: str,
    chaos_mode: str,
    chaos_primitive: str,
    workload_drift_enabled: bool,
) -> str:
    parts = [f"ap={ap_class or 'na'}"]
    if ap_sql_source_kind:
        parts.append(f"ap_sql={ap_sql_source_kind}")
    if htap_check_type and htap_check_type not in {"none", "not-requested"}:
        parts.append(f"probe={htap_check_type}")
    if chaos_mode and chaos_mode not in {"none", "not-requested"}:
        primitive = chaos_primitive or chaos_mode
        parts.append(f"chaos={primitive}")
    if workload_drift_enabled:
        parts.append("workload_drift=on")
    return "; ".join(parts)


def collect_sql_paths(run_dir: Path) -> dict[str, Any]:
    derived_dir = run_dir / "derived"
    inventory = load_json(derived_dir / "workload-sql-set.json")
    tp_inventory = inventory.get("tp", {}) if isinstance(inventory.get("tp"), dict) else {}
    ap_inventory = inventory.get("ap", {}) if isinstance(inventory.get("ap"), dict) else {}
    htap_sections = inventory.get("htap_checks", []) if isinstance(inventory.get("htap_checks"), list) else []

    mixed_baseline = load_json(derived_dir / "mixed-baseline.json")
    ap_baseline = load_json(derived_dir / "ap-baseline.json")

    freshness_path = ""
    sync_path = ""
    for section in htap_sections:
        if not isinstance(section, dict):
            continue
        kind = str(section.get("kind", "")).strip()
        path_value = first_non_empty(section.get("materialized_path_relative"), section.get("materialized_path"))
        if kind == "query-oriented-freshness" and not freshness_path:
            freshness_path = path_value
        if kind == "sync-latency" and not sync_path:
            sync_path = path_value

    if not freshness_path and (derived_dir / "freshness-probe.sql").exists():
        freshness_path = rel_or_abs(derived_dir / "freshness-probe.sql", run_dir)
    if not sync_path and (derived_dir / "sync-latency-probe.sql").exists():
        sync_path = rel_or_abs(derived_dir / "sync-latency-probe.sql", run_dir)

    drift_sql = derived_dir / "query-drift-sample.sql"
    tp_sql = derived_dir / "tp-template-resolved.sql"
    sql_asset_md = derived_dir / "workload-sql-set.md"
    sql_asset_json = derived_dir / "workload-sql-set.json"

    ap_sql_source_kind = first_non_empty(ap_inventory.get("source_kind"), default="")
    if not ap_sql_source_kind:
        if drift_sql.exists():
            ap_sql_source_kind = "drift-sample"
        elif first_non_empty(mixed_baseline.get("ap_query_file"), ap_baseline.get("query_file")):
            ap_sql_source_kind = "fixed-ap-file"
        else:
            ap_sql_source_kind = "unknown"

    ap_sql_path = first_non_empty(
        ap_inventory.get("actual_sql_path_relative"),
        ap_inventory.get("actual_sql_path"),
        rel_or_abs(drift_sql, run_dir) if drift_sql.exists() else "",
        mixed_baseline.get("ap_query_file"),
        ap_baseline.get("query_file"),
        default="",
    )

    return {
        "tp_sql_materialized_path": first_non_empty(
            tp_inventory.get("materialized_path_relative"),
            tp_inventory.get("materialized_path"),
            rel_or_abs(tp_sql, run_dir) if tp_sql.exists() else "",
            default="",
        ),
        "ap_sql_path": ap_sql_path,
        "ap_sql_source_kind": ap_sql_source_kind,
        "freshness_probe_sql_path": freshness_path,
        "sync_probe_sql_path": sync_path,
        "sql_asset_path": rel_or_abs(sql_asset_md, run_dir) if sql_asset_md.exists() else "",
        "sql_asset_json_path": rel_or_abs(sql_asset_json, run_dir) if sql_asset_json.exists() else "",
        "sql_asset_present": 1 if sql_asset_md.exists() and sql_asset_json.exists() else 0,
    }


def collect_run_record(run_dir: Path) -> dict[str, Any]:
    summary = load_json(run_dir / "summary.json")
    validation = load_json(run_dir / "validation" / "artifact-check.json")
    env_sanity = load_json(run_dir / "validation" / "env-sanity.json")
    recovery = load_json(run_dir / "validation" / "recovery-check.json")
    tp_profile_env = load_env(run_dir / "derived" / "tp-profile.env")
    tp_profile = load_json(run_dir / "derived" / "tp-profile.json")
    report_manifest = load_json(run_dir / "report" / "report-manifest.json")
    report_props = load_env(run_dir / "report" / "run.properties.effective")
    pglab_env = load_env(run_dir / "configs" / "pglab.env")
    ap_profile = load_json(run_dir / "derived" / "ap-profile.json")
    data_drift_profile = load_json(run_dir / "derived" / "data-drift-profile.json")
    data_drift_factor = load_json(run_dir / "derived" / "data-drift-factor.json")
    workload_profile = load_json(run_dir / "derived" / "workload-drift-profile.json")
    tp_baseline = load_json(run_dir / "derived" / "tp-baseline.json")
    ap_baseline = load_json(run_dir / "derived" / "ap-baseline.json")
    mixed_baseline = load_json(run_dir / "derived" / "mixed-baseline.json")
    freshness = load_json(run_dir / "derived" / "freshness-check.json")
    sync_latency = load_json(run_dir / "derived" / "sync-latency.json")
    drift = load_json(run_dir / "derived" / "workload-drift-factor.json")
    waitxact = load_json(run_dir / "derived" / "waitxact-chaos.json")
    deadlock = load_json(run_dir / "derived" / "deadlock-pair-chaos.json")
    spill = load_json(run_dir / "derived" / "spill-pressure-chaos.json")
    chaos_profile = load_json(run_dir / "derived" / "chaos-profile.json")
    cleanup_report = load_json(run_dir / "derived" / "cleanup-report.json")
    target_selector = load_json(run_dir / "derived" / "target-selector.json")
    metrics = parse_tp_metrics(run_dir / "tp" / "freshness-updates.log")

    baseline_kind = derive_baseline_kind(run_dir)
    if mixed_baseline:
        ap_rounds_completed = to_int(mixed_baseline.get("ap_rounds_completed"), 0) or 0
    elif ap_baseline:
        ap_rounds_completed = to_int(ap_baseline.get("rounds_completed"), 0) or 0
    else:
        ap_rounds_completed = 0

    query_class = first_non_empty(
        report_props.get("ap_class"),
        tp_profile_env.get("AP_CLASS"),
        mixed_baseline.get("ap_class"),
        ap_baseline.get("ap_class"),
        summary.get("ap_class"),
        default="na",
    )
    overlap = first_non_empty(
        report_props.get("overlap"),
        tp_profile_env.get("WORKLOAD_OVERLAP"),
        mixed_baseline.get("overlap"),
        summary.get("overlap"),
        default="tp-first",
    )
    chaos_mode = first_non_empty(
        report_props.get("chaos_mode"),
        tp_profile_env.get("CHAOS_MODE"),
        mixed_baseline.get("chaos_mode"),
        summary.get("chaos_mode"),
        default="none",
    )
    chaos_primitive = first_non_empty(
        report_props.get("chaos_primitive"),
        tp_profile_env.get("CHAOS_PRIMITIVE"),
        mixed_baseline.get("chaos_primitive"),
        waitxact.get("primitive"),
        deadlock.get("primitive"),
        spill.get("primitive"),
        chaos_profile.get("injection", {}).get("primitive") if isinstance(chaos_profile.get("injection"), dict) else None,
        default="none",
    )
    htap_check_type = first_non_empty(
        report_props.get("htap_check_type"),
        tp_profile_env.get("HTAP_CHECK_TYPE"),
        mixed_baseline.get("htap_check_type"),
        tp_profile.get("htap_check", {}).get("type") if isinstance(tp_profile.get("htap_check"), dict) else None,
        default="none",
    )
    workload_drift_factor = normalize_float(
        first_non_empty(
            report_props.get("workload_drift_factor"),
            tp_profile_env.get("WORKLOAD_DRIFT_FACTOR"),
            mixed_baseline.get("workload_drift_factor"),
            workload_profile.get("workload_factor"),
            drift.get("workload_factor"),
            default="0",
        )
    )
    workload_drift_sample_size = to_int(
        first_non_empty(
            report_props.get("workload_drift_sample_size"),
            tp_profile_env.get("WORKLOAD_DRIFT_SAMPLE_SIZE"),
            mixed_baseline.get("workload_drift_sample_size"),
            workload_profile.get("sample_size"),
            drift.get("sample_size"),
            default="0",
        ),
        0,
    ) or 0
    workload_drift_base_class = first_non_empty(
        report_props.get("workload_drift_base_class"),
        tp_profile_env.get("WORKLOAD_DRIFT_BASE_CLASS"),
        mixed_baseline.get("workload_drift_base_class"),
        workload_profile.get("base_query_class"),
        drift.get("base_query_class"),
        query_class,
        default="na",
    )
    workload_drift_realized_factor = normalize_float(
        first_non_empty(
            report_props.get("workload_drift_realized_factor"),
            tp_profile_env.get("WORKLOAD_DRIFT_REALIZED_FACTOR"),
            mixed_baseline.get("workload_drift_realized_factor"),
            workload_profile.get("realized_workload_factor"),
            drift.get("realized_workload_factor"),
            default="0",
        )
    )
    freshness_samples = to_int(freshness.get("sample_count"), 0) or 0
    freshness_max_epoch_delta = to_int(freshness.get("max_epoch_delta"), 0) or 0
    freshness_latest_lag_ms = to_int(freshness.get("latest_lag_ms_post_mix"), 0) or 0
    sync_samples = to_int(sync_latency.get("sample_count"), 0) or 0
    sync_max_ms = to_int(sync_latency.get("max_sync_latency_ms"), 0) or 0
    sync_post_ms = to_int(sync_latency.get("post_mix_sync_latency_ms"), 0) or 0

    row: dict[str, Any] = {
        "run_dir": str(run_dir),
        "run_id": summary.get("run_id", ""),
        "run_name": summary.get("run_name", ""),
        "rq": summary.get("rq", ""),
        "system": summary.get("system", ""),
        "lab_runtime_mode": first_non_empty(
            summary.get("lab_runtime_mode"),
            env_sanity.get("lab_runtime_mode"),
            tp_profile_env.get("LAB_RUNTIME_MODE"),
            default="container",
        ),
        "memory_profile": first_non_empty(
            summary.get("memory_profile"),
            env_sanity.get("memory_profile"),
            pglab_env.get("MEMORY_PROFILE"),
            default="",
        ),
        "cgroup_cpu_limit": first_non_empty(
            summary.get("cgroup_cpu_limit"),
            env_sanity.get("cgroup_cpu_limit"),
            pglab_env.get("CGROUP_CPU_LIMIT"),
            default="",
        ),
        "cgroup_memory_limit": first_non_empty(
            summary.get("cgroup_memory_limit"),
            env_sanity.get("cgroup_memory_limit"),
            pglab_env.get("CGROUP_MEMORY_LIMIT"),
            default="",
        ),
        "cgroup_memory_reservation": first_non_empty(
            summary.get("cgroup_memory_reservation"),
            env_sanity.get("cgroup_memory_reservation"),
            pglab_env.get("CGROUP_MEMORY_RESERVATION"),
            default="",
        ),
        "lab_env_file": first_non_empty(
            summary.get("lab_env_file"),
            env_sanity.get("lab_env_file"),
            default="",
        ),
        "compose_project_name": first_non_empty(
            summary.get("compose_project_name"),
            env_sanity.get("compose_project_name"),
            pglab_env.get("COMPOSE_PROJECT_NAME"),
            default="",
        ),
        "postgres_image": first_non_empty(
            summary.get("postgres_image"),
            env_sanity.get("postgres_image"),
            pglab_env.get("POSTGRES_IMAGE"),
            default="",
        ),
        "db_port": first_non_empty(
            summary.get("db_port"),
            pglab_env.get("DB_PORT"),
            default="",
        ),
        "required_extensions": first_non_empty(
            summary.get("required_extensions"),
            format_list(env_sanity.get("required_extensions", [])) if isinstance(env_sanity.get("required_extensions"), list) else None,
            pglab_env.get("OBSERVE_REQUIRED_EXTENSIONS"),
            default="",
        ),
        "required_preload_libraries": first_non_empty(
            summary.get("required_preload_libraries"),
            format_list(env_sanity.get("required_preload_libraries", [])) if isinstance(env_sanity.get("required_preload_libraries"), list) else None,
            pglab_env.get("OBSERVE_REQUIRED_PRELOAD_LIBRARIES"),
            default="",
        ),
        "extension_preflight_ok": to_bool(env_sanity.get("extension_preflight_ok"), False),
        "missing_extensions": format_list(env_sanity.get("missing_extensions", [])) if isinstance(env_sanity.get("missing_extensions"), list) else "",
        "missing_preload_libraries": format_list(env_sanity.get("missing_preload_libraries", [])) if isinstance(env_sanity.get("missing_preload_libraries"), list) else "",
        "dataset": summary.get("dataset", ""),
        "budget_tier": summary.get("budget_tier", ""),
        "tp_pressure": summary.get("tp_pressure", ""),
        "tp_driver": first_non_empty(mixed_baseline.get("tp_driver"), tp_baseline.get("tp_driver"), metrics.get("driver"), tp_profile_env.get("JOB_TP_DRIVER"), tp_profile.get("driver"), default="pgbench"),
        "ap_class": query_class,
        "overlap": overlap,
        "variant": summary.get("variant", ""),
        "seed": to_int(summary.get("seed"), 0) or 0,
        "status": summary.get("status", ""),
        "baseline_kind": baseline_kind,
        "validation_complete": to_bool(validation.get("validation_complete"), False),
        "validation_missing_count": len(validation.get("missing_files", []) or []),
        "recovered": to_bool(recovery.get("recovered"), False),
        "recovery_time_ms": to_int(recovery.get("time_to_recovery_ms"), 0) or 0,
        "recovery_debt": recovery.get("recovery_debt", ""),
        "tp_tps": metrics.get("tp_tps"),
        "tp_latency_avg_ms": metrics.get("tp_latency_avg_ms"),
        "tp_transactions": metrics.get("tp_transactions"),
        "tp_threads": to_int(tp_profile_env.get("JOB_TP_THREADS"), 0) or 0,
        "tp_terminals": to_int(tp_profile_env.get("JOB_TP_TERMINALS"), 0) or 0,
        "ap_rounds_completed": ap_rounds_completed,
        "ap_parallelism": to_int(first_non_empty(report_props.get("ap_parallelism"), tp_profile_env.get("AP_PARALLELISM"), ap_profile.get("parallelism"), default="0"), 0) or 0,
        "cleanup_profile": first_non_empty(report_props.get("cleanup_profile"), tp_profile_env.get("CHAOS_CLEANUP_PROFILE"), chaos_profile.get("cleanup_profile"), cleanup_report.get("cleanup_profile"), default="pg-default"),
        "safety_level": first_non_empty(report_props.get("safety_level"), tp_profile_env.get("CHAOS_SAFETY_LEVEL"), chaos_profile.get("safety_level"), default="mainline"),
        "feature_scope": first_non_empty(
            report_props.get("feature_scope"),
            "|".join(str(item) for item in data_drift_profile.get("feature_scope", []) if str(item).strip()) if isinstance(data_drift_profile.get("feature_scope"), list) else None,
            "|".join(str(item) for item in workload_profile.get("feature_scope", []) if str(item).strip()) if isinstance(workload_profile.get("feature_scope"), list) else None,
            tp_profile_env.get("DRIFT_FEATURE_SCOPE"),
            default="",
        ),
        "data_drift_enabled": to_bool(report_props.get("data_drift_enabled"), False) or to_bool(data_drift_profile.get("enabled"), False),
        "data_drift_factor": normalize_float(first_non_empty(report_props.get("data_drift_factor"), data_drift_factor.get("data_factor"), data_drift_profile.get("data_factor"), default="0")),
        "report_bundle_status": first_non_empty(report_manifest.get("status"), default="absent"),
        "report_bundle_missing_count": len(report_manifest.get("missing_required_artifacts", []) or []),
        "freshness_samples": freshness_samples,
        "freshness_max_epoch_delta": freshness_max_epoch_delta,
        "freshness_latest_lag_ms": freshness_latest_lag_ms,
        "sync_samples": sync_samples,
        "sync_max_ms": sync_max_ms,
        "sync_post_ms": sync_post_ms,
        "workload_drift_enabled": to_bool(tp_profile_env.get("WORKLOAD_DRIFT_ENABLED"), False) or (run_dir / "derived" / "query-drift-sample.sql").exists(),
        "workload_drift_factor": workload_drift_factor,
        "workload_drift_sample_size": workload_drift_sample_size,
        "workload_drift_base_class": workload_drift_base_class,
        "workload_drift_realized_factor": workload_drift_realized_factor,
        "chaos_mode": chaos_mode,
        "chaos_primitive": chaos_primitive,
        "chaos_status": first_non_empty(
            tp_profile_env.get("CHAOS_STATUS"),
            mixed_baseline.get("chaos_status"),
            waitxact.get("status"),
            deadlock.get("status"),
            spill.get("status"),
            cleanup_report.get("status"),
            default="not-requested",
        ),
        "htap_check_type": htap_check_type,
        "wait_duration_ms": to_int(waitxact.get("wait_duration_ms"), 0) or 0,
        "deadlock_detected_count": to_int(deadlock.get("deadlock_detected_count"), 0) or 0,
        "deadlock_abort_count": to_int(deadlock.get("aborted_session_count"), 0) or 0,
        "spill_temp_files_delta": to_int(spill.get("temp_files_delta"), 0) or 0,
        "spill_temp_bytes_delta": to_int(spill.get("temp_bytes_delta"), 0) or 0,
        "spill_execution_rate_qps": normalize_float(spill.get("actual_rate_qps")),
        "adapter_limited": summary.get("status", "") == "adapter-limited",
        "target_selector": target_selector.get("selection_expr", ""),
    }

    row.update(collect_sql_paths(run_dir))

    tier_group = infer_tier_group(str(row.get("variant", "")), str(row.get("run_name", "")), str(row.get("run_id", "")))
    figure_group = infer_figure_group(tier_group, str(row.get("variant", "")), str(row.get("htap_check_type", "")))
    figure_meta = FIGURE_GROUPS[figure_group]
    family_group = infer_family_group(figure_group)
    family_member = infer_family_member(
        figure_group,
        str(row.get("variant", "")),
        str(row.get("chaos_primitive", "")),
        str(row.get("htap_check_type", "")),
    )

    row.update(
        {
            "tier_group": tier_group,
            "figure_group": figure_group,
            "figure_group_title": figure_meta["title"],
            "figure_group_slot": figure_meta["slot"],
            "figure_group_metrics": "|".join(figure_meta["metrics"]),
            "family_group": family_group,
            "family_member": family_member,
            "workload_signature": build_workload_signature(
                str(row.get("ap_class", "")),
                str(row.get("ap_sql_source_kind", "")),
                str(row.get("htap_check_type", "")),
                str(row.get("chaos_mode", "")),
                str(row.get("chaos_primitive", "")),
                bool(row.get("workload_drift_enabled", False)),
            ),
        }
    )
    return row


def group_records(records: list[dict[str, Any]], fields: list[str]) -> list[dict[str, Any]]:
    grouped: dict[tuple[Any, ...], list[dict[str, Any]]] = defaultdict(list)
    for record in records:
        grouped[tuple(record.get(field, "") for field in fields)].append(record)

    output: list[dict[str, Any]] = []
    for key in sorted(grouped.keys(), key=lambda item: tuple(str(value) for value in item)):
        rows = grouped[key]
        aggregated: dict[str, Any] = {field: rows[0].get(field, "") for field in fields}
        aggregated["run_count"] = len(rows)
        aggregated["seeds"] = format_list([record.get("seed", "") for record in rows])
        aggregated["run_ids"] = format_list([record.get("run_id", "") for record in rows])
        aggregated["run_names"] = format_list([record.get("run_name", "") for record in rows])
        aggregated["systems"] = format_list(sorted({str(record.get("system", "")) for record in rows if record.get("system", "") != ""}))
        aggregated["variants"] = format_list(sorted({str(record.get("variant", "")) for record in rows if record.get("variant", "") != ""}))
        aggregated["status_set"] = format_list(sorted({str(record.get("status", "")) for record in rows if record.get("status", "") != ""}))
        aggregated["validation_complete_runs"] = sum(1 for record in rows if to_bool(record.get("validation_complete"), False))
        aggregated["recovered_runs"] = sum(1 for record in rows if to_bool(record.get("recovered"), False))
        aggregated["adapter_limited_runs"] = sum(1 for record in rows if to_bool(record.get("adapter_limited"), False))
        aggregated["sql_asset_present_runs"] = sum(1 for record in rows if to_int(record.get("sql_asset_present"), 0) == 1)
        for metric in NUMERIC_METRICS:
            values = [record.get(metric) for record in rows if record.get(metric) is not None]
            avg, std = mean_std(values)
            aggregated[f"{metric}_mean"] = avg
            aggregated[f"{metric}_std"] = std
        output.append(aggregated)
    return output


def write_csv(path: Path, rows: list[dict[str, Any]], columns: list[str]) -> None:
    with path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=columns)
        writer.writeheader()
        for row in rows:
            out = {column: row.get(column, "") for column in columns}
            writer.writerow(out)


def sorted_records(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return sorted(
        records,
        key=lambda row: (
            TIER_ORDER.get(str(row.get("tier_group", "")), 99),
            FIGURE_ORDER.get(str(row.get("figure_group", "")), 99),
            str(row.get("family_member", "")),
            str(row.get("variant", "")),
            str(row.get("run_id", "")),
        ),
    )


def render_figure_groups(records: list[dict[str, Any]]) -> str:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for record in records:
        grouped[str(record.get("figure_group", ""))].append(record)

    profiles = sorted({str(record.get("memory_profile", "")).strip() or "unlabeled" for record in records})
    parts = [
        "# Mixed-workload figure groups\n\n",
        f"- total_runs: `{len(records)}`\n",
        f"- figure_groups: `{len(grouped)}`\n",
        f"- memory_profiles: `{', '.join(profiles)}`\n",
        "- each row links to the per-run SQL asset that captures TP / AP / probe / chaos SQL together.\n\n",
    ]

    for figure_group in sorted(grouped.keys(), key=lambda key: FIGURE_ORDER.get(key, 99)):
        meta = FIGURE_GROUPS.get(figure_group, {"title": figure_group, "slot": "", "comparison": "", "metrics": []})
        rows = sorted_records(grouped[figure_group])
        representative_rows: list[dict[str, Any]] = []
        seen_members: set[str] = set()
        for row in rows:
            member = str(row.get("family_member", ""))
            if member in seen_members:
                continue
            seen_members.add(member)
            representative_rows.append(row)

        parts.extend(
            [
                f"## {figure_group} — {meta['title']}\n\n",
                f"- recommended_slot: `{meta['slot']}`\n",
                f"- main_comparison: {meta['comparison']}\n",
                f"- suggested_metrics: `{', '.join(meta['metrics'])}`\n",
                f"- run_count: `{len(rows)}`\n\n",
                "### representative SQL assets\n\n",
                rows_to_markdown(
                    [stringify_row(row, [
                        "memory_profile",
                        "family_member",
                        "variant",
                        "run_id",
                        "ap_sql_source_kind",
                        "sql_asset_path",
                    ]) for row in representative_rows],
                    ["memory_profile", "family_member", "variant", "run_id", "ap_sql_source_kind", "sql_asset_path"],
                ),
                "\n### runs\n\n",
                rows_to_markdown(
                    [stringify_row(row, [
                        "memory_profile",
                        "tier_group",
                        "family_member",
                        "variant",
                        "run_id",
                        "tp_pressure",
                        "ap_class",
                        "chaos_primitive",
                        "htap_check_type",
                        "tp_tps",
                        "tp_latency_avg_ms",
                        "sql_asset_path",
                    ]) for row in rows],
                    [
                        "memory_profile",
                        "tier_group",
                        "family_member",
                        "variant",
                        "run_id",
                        "tp_pressure",
                        "ap_class",
                        "chaos_primitive",
                        "htap_check_type",
                        "tp_tps",
                        "tp_latency_avg_ms",
                        "sql_asset_path",
                    ],
                ),
                "\n",
            ]
        )
    return "".join(parts)


def main() -> None:
    args = parse_args()
    run_dirs = resolve_run_dirs(args)
    if not run_dirs:
        raise SystemExit("no run dirs were provided")

    output_dir = Path(args.output_dir).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    records = sorted_records([collect_run_record(run_dir) for run_dir in run_dirs])

    runlist_path = output_dir / "runlist.txt"
    runlist_path.write_text("\n".join(record["run_dir"] for record in records) + "\n", encoding="utf-8")

    run_index_columns = [
        "run_dir",
        "run_id",
        "run_name",
        "rq",
        "system",
        "lab_runtime_mode",
        "memory_profile",
        "cgroup_cpu_limit",
        "cgroup_memory_limit",
        "cgroup_memory_reservation",
        "compose_project_name",
        "postgres_image",
        "db_port",
        "lab_env_file",
        "required_extensions",
        "required_preload_libraries",
        "extension_preflight_ok",
        "missing_extensions",
        "missing_preload_libraries",
        "dataset",
        "budget_tier",
        "tp_pressure",
        "tp_driver",
        "ap_class",
        "overlap",
        "variant",
        "seed",
        "status",
        "tier_group",
        "figure_group",
        "figure_group_title",
        "figure_group_slot",
        "family_group",
        "family_member",
        "workload_signature",
        "baseline_kind",
        "validation_complete",
        "validation_missing_count",
        "recovered",
        "recovery_time_ms",
        "tp_tps",
        "tp_latency_avg_ms",
        "tp_transactions",
        "ap_rounds_completed",
        "ap_parallelism",
        "cleanup_profile",
        "safety_level",
        "feature_scope",
        "data_drift_enabled",
        "data_drift_factor",
        "report_bundle_status",
        "report_bundle_missing_count",
        "freshness_samples",
        "freshness_max_epoch_delta",
        "freshness_latest_lag_ms",
        "sync_samples",
        "sync_max_ms",
        "sync_post_ms",
        "workload_drift_enabled",
        "workload_drift_factor",
        "workload_drift_sample_size",
        "workload_drift_base_class",
        "workload_drift_realized_factor",
        "chaos_mode",
        "chaos_primitive",
        "chaos_status",
        "htap_check_type",
        "wait_duration_ms",
        "deadlock_detected_count",
        "deadlock_abort_count",
        "spill_temp_files_delta",
        "spill_temp_bytes_delta",
        "spill_execution_rate_qps",
        "adapter_limited",
        "target_selector",
        "tp_sql_materialized_path",
        "ap_sql_path",
        "ap_sql_source_kind",
        "freshness_probe_sql_path",
        "sync_probe_sql_path",
        "sql_asset_path",
        "sql_asset_json_path",
        "sql_asset_present",
        "figure_group_metrics",
    ]

    results_table_columns = [
        "memory_profile",
        "cgroup_cpu_limit",
        "cgroup_memory_limit",
        "figure_group",
        "family_group",
        "family_member",
        "variant",
        "run_id",
        "tp_pressure",
        "ap_class",
        "chaos_primitive",
        "htap_check_type",
        "tp_tps",
        "tp_latency_avg_ms",
        "wait_duration_ms",
        "deadlock_detected_count",
        "spill_temp_bytes_delta",
        "freshness_latest_lag_ms",
        "sync_post_ms",
        "workload_drift_realized_factor",
        "sql_asset_path",
    ]

    run_index_rows = [stringify_row(record, run_index_columns) for record in records]
    results_table_rows = [stringify_row(record, results_table_columns) for record in records]

    seed_summary_rows = group_records(records, SEED_GROUP_FIELDS)
    comparison_rows = group_records(records, COMPARISON_GROUP_FIELDS)
    family_summary_rows = group_records(records, FAMILY_GROUP_FIELDS)

    run_index_path = output_dir / "run-index.csv"
    results_table_path = output_dir / "results-table.csv"
    seed_summary_path = output_dir / "seed-summary.csv"
    comparison_path = output_dir / "comparison-index.csv"
    family_summary_path = output_dir / "family-summary.csv"
    figure_groups_path = output_dir / "figure-groups.md"
    summary_md_path = output_dir / "summary.md"

    write_csv(run_index_path, run_index_rows, run_index_columns)
    write_csv(results_table_path, results_table_rows, results_table_columns)

    seed_summary_columns = [
        *SEED_GROUP_FIELDS,
        "run_count",
        "seeds",
        "run_ids",
        "status_set",
        "validation_complete_runs",
        "recovered_runs",
        "adapter_limited_runs",
        "sql_asset_present_runs",
    ] + [f"{metric}_mean" for metric in NUMERIC_METRICS] + [f"{metric}_std" for metric in NUMERIC_METRICS]
    write_csv(seed_summary_path, [stringify_row(row, seed_summary_columns) for row in seed_summary_rows], seed_summary_columns)

    comparison_columns = [
        *COMPARISON_GROUP_FIELDS,
        "run_count",
        "systems",
        "variants",
        "seeds",
        "run_ids",
        "status_set",
        "validation_complete_runs",
        "recovered_runs",
        "adapter_limited_runs",
        "sql_asset_present_runs",
        "tp_tps_mean",
        "tp_latency_avg_ms_mean",
        "wait_duration_ms_mean",
        "deadlock_detected_count_mean",
        "spill_temp_bytes_delta_mean",
        "freshness_latest_lag_ms_mean",
        "sync_post_ms_mean",
        "workload_drift_realized_factor_mean",
    ]
    write_csv(comparison_path, [stringify_row(row, comparison_columns) for row in comparison_rows], comparison_columns)

    family_summary_columns = [
        *FAMILY_GROUP_FIELDS,
        "run_count",
        "variants",
        "run_ids",
        "status_set",
        "validation_complete_runs",
        "recovered_runs",
        "sql_asset_present_runs",
        "tp_tps_mean",
        "tp_latency_avg_ms_mean",
        "wait_duration_ms_mean",
        "deadlock_detected_count_mean",
        "spill_temp_bytes_delta_mean",
        "freshness_latest_lag_ms_mean",
        "sync_post_ms_mean",
        "workload_drift_realized_factor_mean",
    ]
    write_csv(family_summary_path, [stringify_row(row, family_summary_columns) for row in family_summary_rows], family_summary_columns)

    figure_groups_path.write_text(render_figure_groups(records), encoding="utf-8")

    figure_group_overview_rows = []
    for figure_group in sorted({str(record.get("figure_group", "")) for record in records}, key=lambda key: FIGURE_ORDER.get(key, 99)):
        rows = [record for record in records if str(record.get("figure_group", "")) == figure_group]
        meta = FIGURE_GROUPS.get(figure_group, {"title": figure_group, "slot": "", "comparison": "", "metrics": []})
        figure_group_overview_rows.append(
            {
                "figure_group": figure_group,
                "title": meta["title"],
                "slot": meta["slot"],
                "comparison": meta["comparison"],
                "metrics": ", ".join(meta["metrics"]),
                "run_count": len(rows),
            }
        )

    profile_labels = sorted({str(record.get("memory_profile", "")).strip() or "unlabeled" for record in records})
    sql_asset_present_count = sum(1 for record in records if to_int(record.get("sql_asset_present"), 0) == 1)
    md_parts = [
        "# Mixed-workload matrix summary\n\n",
        f"- run dirs summarized: {len(records)}\n",
        f"- memory profiles: `{', '.join(profile_labels)}`\n",
        f"- sql assets present: {sql_asset_present_count}/{len(records)}\n",
        f"- output dir: `{output_dir}`\n",
        "- figure groups follow the paper-facing organization rather than raw execution order.\n\n",
        "## Figure-group coverage\n\n",
        rows_to_markdown([stringify_row(row, ["figure_group", "title", "slot", "comparison", "metrics", "run_count"]) for row in figure_group_overview_rows], ["figure_group", "title", "slot", "comparison", "metrics", "run_count"]),
        "\n## Main results table\n\n",
        rows_to_markdown(
            [stringify_row(row, [
                "memory_profile",
                "figure_group",
                "family_member",
                "variant",
                "run_id",
                "tp_tps",
                "tp_latency_avg_ms",
                "wait_duration_ms",
                "deadlock_detected_count",
                "spill_temp_bytes_delta",
                "freshness_latest_lag_ms",
                "sync_post_ms",
                "workload_drift_realized_factor",
                "sql_asset_path",
            ]) for row in records],
            [
                "memory_profile",
                "figure_group",
                "family_member",
                "variant",
                "run_id",
                "tp_tps",
                "tp_latency_avg_ms",
                "wait_duration_ms",
                "deadlock_detected_count",
                "spill_temp_bytes_delta",
                "freshness_latest_lag_ms",
                "sync_post_ms",
                "workload_drift_realized_factor",
                "sql_asset_path",
            ],
        ),
        "\n## Family summary\n\n",
        rows_to_markdown(
            [stringify_row(row, [
                "memory_profile",
                "figure_group",
                "family_member",
                "run_count",
                "tp_tps_mean",
                "tp_latency_avg_ms_mean",
                "wait_duration_ms_mean",
                "deadlock_detected_count_mean",
                "spill_temp_bytes_delta_mean",
                "freshness_latest_lag_ms_mean",
                "sync_post_ms_mean",
                "workload_drift_realized_factor_mean",
                "sql_asset_present_runs",
            ]) for row in family_summary_rows],
            [
                "memory_profile",
                "figure_group",
                "family_member",
                "run_count",
                "tp_tps_mean",
                "tp_latency_avg_ms_mean",
                "wait_duration_ms_mean",
                "deadlock_detected_count_mean",
                "spill_temp_bytes_delta_mean",
                "freshness_latest_lag_ms_mean",
                "sync_post_ms_mean",
                "workload_drift_realized_factor_mean",
                "sql_asset_present_runs",
            ],
        ),
        "\n## Result package\n\n",
        f"- runlist: `{runlist_path.name}`\n",
        f"- run index: `{run_index_path.name}`\n",
        f"- results table: `{results_table_path.name}`\n",
        f"- seed summary: `{seed_summary_path.name}`\n",
        f"- comparison index: `{comparison_path.name}`\n",
        f"- family summary: `{family_summary_path.name}`\n",
        f"- figure groups: `{figure_groups_path.name}`\n",
    ]
    summary_md_path.write_text("".join(md_parts), encoding="utf-8")

    report = {
        "run_count": len(records),
        "sql_asset_present_count": sql_asset_present_count,
        "runlist_txt": runlist_path.name,
        "run_index_csv": run_index_path.name,
        "results_table_csv": results_table_path.name,
        "seed_summary_csv": seed_summary_path.name,
        "comparison_index_csv": comparison_path.name,
        "family_summary_csv": family_summary_path.name,
        "figure_groups_md": figure_groups_path.name,
        "summary_md": summary_md_path.name,
    }
    (output_dir / "summary.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
