#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import shlex
from pathlib import Path


ROOT_REQUIRED_FILES = [
    "summary.json",
    "manifest.env",
    "manifest.resolved.txt",
    "stdout.log",
    "stderr.log",
]

DIRECTORIES_TO_INDEX = [
    "validation",
    "explainability",
    "derived",
    "htapcheck",
    "observability",
    "tp",
    "ap",
    "lock",
    "chaos",
    "report",
    "figures",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", required=True)
    return parser.parse_args()


def load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def load_env(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
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


def load_run_status(run_dir: Path) -> str:
    path = run_dir / "run-status.txt"
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8").strip()


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


def first_non_empty(*values: object, default: str = "") -> str:
    for value in values:
        if value is None:
            continue
        text = str(value).strip()
        if text:
            return text
    return default


def format_bool(value: object, default: bool = False) -> str:
    if value is None or value == "":
        return "true" if default else "false"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return "true" if value else "false"
    text = str(value).strip().lower()
    if text in {"1", "true", "yes", "on"}:
        return "true"
    if text in {"0", "false", "no", "off"}:
        return "false"
    return "true" if default else "false"


def format_number(value: object, default: str = "") -> str:
    if value is None or value == "":
        return default
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, int):
        return str(value)
    try:
        number = float(value)
    except (TypeError, ValueError):
        return default
    text = f"{number:.6f}".rstrip("0").rstrip(".")
    return text if text else "0"


def shell_value(value: object) -> str:
    text = str(value)
    if text == "":
        return "''"
    if any(ch in text for ch in " \t\n\r'\"\\"):
        return "'" + text.replace("'", "'\\''") + "'"
    return text


def scope_text(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, (list, tuple)):
        return "|".join(str(item).strip() for item in value if str(item).strip())
    text = str(value).strip()
    if not text:
        return ""
    if "|" in text:
        return text
    if "," in text:
        parts = [part.strip() for part in text.split(",") if part.strip()]
        return "|".join(parts)
    return text


def add_entry(entries: dict[str, dict[str, object]], run_dir: Path, rel_path: str, category: str, required: bool = False, exists: bool | None = None) -> None:
    rel_path = rel_path.replace("\\", "/")
    path = run_dir / rel_path
    if exists is None:
        exists = path.exists()
    entry = entries.get(rel_path)
    if entry is None:
        entries[rel_path] = {
            "path": rel_path,
            "category": category,
            "required": required,
            "exists": bool(exists),
        }
        return
    entry["required"] = bool(entry.get("required", False) or required)
    if exists is not None:
        entry["exists"] = bool(entry.get("exists", False) or exists)
    if not entry.get("category"):
        entry["category"] = category


def collect_artifacts(run_dir: Path, required_paths: list[str], property_path: str, manifest_path: str) -> list[dict[str, object]]:
    entries: dict[str, dict[str, object]] = {}

    for rel_path in ROOT_REQUIRED_FILES:
        add_entry(entries, run_dir, rel_path, "root", required=True)

    for directory in DIRECTORIES_TO_INDEX:
        directory_path = run_dir / directory
        if not directory_path.exists():
            continue
        for path in sorted(directory_path.rglob("*")):
            if path.is_file():
                rel_path = path.relative_to(run_dir).as_posix()
                add_entry(entries, run_dir, rel_path, directory, required=False)

    add_entry(entries, run_dir, property_path, "report", required=True, exists=True)
    add_entry(entries, run_dir, manifest_path, "report", required=True, exists=True)

    for rel_path in required_paths:
        add_entry(entries, run_dir, rel_path, "report", required=True)

    return sorted(entries.values(), key=lambda item: str(item["path"]))


def build_properties(run_dir: Path) -> dict[str, str]:
    summary = load_json(run_dir / "summary.json")
    validation = load_json(run_dir / "validation" / "artifact-check.json")
    recovery = load_json(run_dir / "validation" / "recovery-check.json")
    tp_profile_env = load_env(run_dir / "derived" / "tp-profile.env")
    tp_profile = load_json(run_dir / "derived" / "tp-profile.json")
    ap_profile = load_json(run_dir / "derived" / "ap-profile.json")
    freshness_profile = load_json(run_dir / "derived" / "freshness-profile.json")
    freshness = load_json(run_dir / "derived" / "freshness-check.json")
    sync_profile = load_json(run_dir / "derived" / "sync-latency-profile.json")
    sync_latency = load_json(run_dir / "derived" / "sync-latency.json")
    workload_profile = load_json(run_dir / "derived" / "workload-drift-profile.json")
    workload_factor = load_json(run_dir / "derived" / "workload-drift-factor.json")
    data_profile = load_json(run_dir / "derived" / "data-drift-profile.json")
    data_factor = load_json(run_dir / "derived" / "data-drift-factor.json")
    chaos_profile = load_json(run_dir / "derived" / "chaos-profile.json")
    cleanup_report = load_json(run_dir / "derived" / "cleanup-report.json")
    report_manifest = load_json(run_dir / "report" / "report-manifest.json")
    plot_status = load_json(run_dir / "validation" / "plot-status.json")
    plot_manifest = load_json(run_dir / "figures" / "plot-manifest.json")
    capabilities = load_json(run_dir / "observability" / "timeline" / "capabilities.json")
    run_status = load_run_status(run_dir)
    tp_metrics = parse_tp_metrics(run_dir / "tp" / "freshness-updates.log")

    feature_scope = scope_text(
        first_non_empty(
            data_profile.get("feature_scope"),
            workload_profile.get("feature_scope"),
            tp_profile_env.get("DRIFT_FEATURE_SCOPE"),
            default="",
        )
    )
    effective_status = first_non_empty(run_status, summary.get("status"), default="")
    if effective_status in {"", "failed"} and validation.get("validation_complete") is True:
        effective_status = "completed"

    properties = {
        "run_id": first_non_empty(summary.get("run_id"), tp_profile_env.get("RUN_ID")),
        "run_name": first_non_empty(summary.get("run_name"), tp_profile_env.get("RUN_NAME")),
        "rq": first_non_empty(summary.get("rq"), tp_profile_env.get("RQ")),
        "system": first_non_empty(summary.get("system"), tp_profile_env.get("SYSTEM")),
        "dataset": first_non_empty(summary.get("dataset"), tp_profile_env.get("DATASET")),
        "budget_tier": first_non_empty(summary.get("budget_tier"), tp_profile_env.get("BUDGET_TIER")),
        "tp_pressure": first_non_empty(summary.get("tp_pressure"), tp_profile_env.get("TP_PRESSURE")),
        "ap_class": first_non_empty(summary.get("ap_class"), tp_profile_env.get("AP_CLASS"), ap_profile.get("class")),
        "ap_parallelism": format_number(first_non_empty(tp_profile_env.get("AP_PARALLELISM"), ap_profile.get("parallelism"), default="0"), default="0"),
        "overlap": first_non_empty(summary.get("overlap"), tp_profile_env.get("WORKLOAD_OVERLAP"), tp_profile_env.get("OVERLAP")),
        "variant": first_non_empty(summary.get("variant"), tp_profile_env.get("VARIANT")),
        "seed": format_number(first_non_empty(summary.get("seed"), tp_profile_env.get("SEED"), default="0"), default="0"),
        "status": effective_status,
        "baseline_kind": "mixed" if (run_dir / "derived" / "mixed-baseline.json").exists() else ("ap-only" if (run_dir / "derived" / "ap-baseline.json").exists() else ("tp-only" if (run_dir / "derived" / "tp-baseline.json").exists() else ("generator" if (run_dir / "derived" / "generator").exists() else "unknown"))),
        "validation_complete": format_bool(validation.get("validation_complete"), False),
        "validation_missing_count": format_number(len(validation.get("missing_files", []) or []), default="0"),
        "recovered": format_bool(recovery.get("recovered"), False),
        "recovery_time_ms": format_number(recovery.get("time_to_recovery_ms"), default="0"),
        "tp_tps": format_number(first_non_empty(summary.get("tp_tps"), tp_metrics.get("tp_tps"), default=""), default=""),
        "tp_latency_avg_ms": format_number(first_non_empty(summary.get("tp_latency_avg_ms"), tp_metrics.get("tp_latency_avg_ms"), default=""), default=""),
        "tp_transactions": format_number(first_non_empty(summary.get("tp_transactions"), tp_metrics.get("tp_transactions"), default=""), default=""),
        "tp_driver": first_non_empty(summary.get("tp_driver"), tp_metrics.get("driver"), tp_profile_env.get("JOB_TP_DRIVER"), tp_profile.get("driver"), default="pgbench"),
        "tp_threads": format_number(tp_profile_env.get("JOB_TP_THREADS"), default="0"),
        "tp_terminals": format_number(tp_profile_env.get("JOB_TP_TERMINALS"), default="0"),
        "ap_rounds_completed": format_number(
            first_non_empty(
                load_json(run_dir / "derived" / "mixed-baseline.json").get("ap_rounds_completed"),
                load_json(run_dir / "derived" / "ap-baseline.json").get("rounds_completed"),
                default="0",
            ),
            default="0",
        ),
        "ap_parallelism": format_number(first_non_empty(tp_profile_env.get("AP_PARALLELISM"), ap_profile.get("parallelism"), default="0"), default="0"),
        "observe_sampling_interval_seconds": format_number(tp_profile_env.get("OBSERVE_SAMPLING_INTERVAL_SECONDS"), default="0"),
        "observe_metrics_profile": first_non_empty(tp_profile_env.get("OBSERVE_METRICS_PROFILE"), default="mixed-default"),
        "plot_profile": first_non_empty(tp_profile_env.get("PLOT_PROFILE"), default="mixed-default"),
        "plot_status": first_non_empty(plot_status.get("status"), default="not-requested"),
        "plot_generated_file_count": format_number(len(plot_manifest.get("generated_files", []) or []), default="0"),
        "system_memory_observation": first_non_empty(capabilities.get("system_memory_observation"), default="unknown"),
        "session_memory_observation": first_non_empty(capabilities.get("session_memory_observation"), default="unknown"),
        "kcache_observation": first_non_empty(capabilities.get("kcache_observation"), default="unknown"),
        "freshness_samples": format_number(freshness.get("sample_count"), default="0"),
        "freshness_max_epoch_delta": format_number(freshness.get("max_epoch_delta"), default="0"),
        "freshness_latest_lag_ms": format_number(freshness.get("latest_lag_ms_post_mix"), default="0"),
        "sync_samples": format_number(sync_latency.get("sample_count"), default="0"),
        "sync_max_ms": format_number(sync_latency.get("max_sync_latency_ms"), default="0"),
        "sync_post_ms": format_number(sync_latency.get("post_mix_sync_latency_ms"), default="0"),
        "workload_drift_enabled": format_bool(tp_profile_env.get("WORKLOAD_DRIFT_ENABLED"), False),
        "data_drift_enabled": format_bool(data_profile.get("enabled"), False),
        "data_drift_factor": format_number(first_non_empty(tp_profile_env.get("DATA_DRIFT_FACTOR"), data_factor.get("data_factor"), data_profile.get("data_factor"), default="0"), default="0"),
        "workload_drift_factor": format_number(first_non_empty(tp_profile_env.get("WORKLOAD_DRIFT_FACTOR"), workload_factor.get("workload_factor"), workload_profile.get("workload_factor"), default="0"), default="0"),
        "workload_drift_sample_size": format_number(first_non_empty(tp_profile_env.get("WORKLOAD_DRIFT_SAMPLE_SIZE"), workload_factor.get("sample_size"), workload_profile.get("sample_size"), default="0"), default="0"),
        "workload_drift_base_class": first_non_empty(
            tp_profile_env.get("WORKLOAD_DRIFT_BASE_CLASS"),
            workload_factor.get("base_query_class"),
            workload_profile.get("base_query_class"),
            tp_profile_env.get("AP_CLASS"),
            default="na",
        ),
        "workload_drift_realized_factor": format_number(
            first_non_empty(
                tp_profile_env.get("WORKLOAD_DRIFT_REALIZED_FACTOR"),
                workload_factor.get("realized_workload_factor"),
                workload_profile.get("realized_workload_factor"),
                default="0",
            ),
            default="0",
        ),
        "feature_scope": feature_scope,
        "chaos_mode": first_non_empty(tp_profile_env.get("CHAOS_MODE"), chaos_profile.get("mode"), default="none"),
        "chaos_primitive": first_non_empty(tp_profile_env.get("CHAOS_PRIMITIVE"), chaos_profile.get("injection", {}).get("primitive") if isinstance(chaos_profile.get("injection"), dict) else None, default="none"),
        "safety_level": first_non_empty(tp_profile_env.get("CHAOS_SAFETY_LEVEL"), chaos_profile.get("safety_level"), default="mainline"),
        "cleanup_profile": first_non_empty(tp_profile_env.get("CHAOS_CLEANUP_PROFILE"), chaos_profile.get("cleanup_profile"), cleanup_report.get("cleanup_profile"), default="pg-default"),
        "chaos_status": first_non_empty(tp_profile_env.get("CHAOS_STATUS"), chaos_profile.get("status"), cleanup_report.get("status"), default="not-requested"),
        "htap_check_type": first_non_empty(tp_profile_env.get("HTAP_CHECK_TYPE"), tp_profile.get("htap_check", {}).get("type") if isinstance(tp_profile.get("htap_check"), dict) else None, default="none"),
        "wait_duration_ms": format_number(load_json(run_dir / "derived" / "waitxact-chaos.json").get("wait_duration_ms"), default="0"),
        "deadlock_detected_count": format_number(load_json(run_dir / "derived" / "deadlock-pair-chaos.json").get("deadlock_detected_count"), default="0"),
        "deadlock_abort_count": format_number(load_json(run_dir / "derived" / "deadlock-pair-chaos.json").get("aborted_session_count"), default="0"),
        "spill_temp_files_delta": format_number(load_json(run_dir / "derived" / "spill-pressure-chaos.json").get("temp_files_delta"), default="0"),
        "spill_temp_bytes_delta": format_number(load_json(run_dir / "derived" / "spill-pressure-chaos.json").get("temp_bytes_delta"), default="0"),
        "spill_execution_rate_qps": format_number(load_json(run_dir / "derived" / "spill-pressure-chaos.json").get("actual_rate_qps"), default="0"),
        "report_bundle_present": "true",
        "report_bundle_required_count": format_number(len(report_manifest.get("required_artifacts", []) or []), default="0"),
    }

    return properties


def build_required_artifacts(run_dir: Path) -> list[str]:
    required = {
        "summary.json",
        "manifest.env",
        "manifest.resolved.txt",
        "stdout.log",
        "stderr.log",
        "validation/artifact-check.json",
        "validation/explainability.json",
        "explainability/event-timeline.md",
        "explainability/top-findings.md",
        "derived/tp-profile.json",
        "derived/tp-profile.env",
        "derived/target-selector.json",
        "derived/hotspot-selector.json",
        "derived/cardinality-profile.json",
        "report/run.properties.effective",
        "report/report-manifest.json",
    }

    cleanup_policy = load_json(run_dir / "derived" / "cleanup-policy.json")
    for rel_path in cleanup_policy.get("required_artifacts", []) or []:
        required.add(str(rel_path))

    if (run_dir / "derived" / "ap-profile.json").exists():
        required.add("derived/ap-profile.json")
    if (run_dir / "derived" / "tp-baseline.json").exists() or (run_dir / "derived" / "mixed-baseline.json").exists():
        required.update({
            "tp/freshness-updates.log",
            "tp/progress.csv",
            "tp/summary.json",
        })
    if (run_dir / "validation" / "recovery-check.json").exists():
        required.add("validation/recovery-check.json")
    if (run_dir / "derived" / "freshness-profile.json").exists():
        required.update({
            "derived/freshness-profile.json",
            "derived/freshness-check.json",
            "htapcheck/freshness.csv",
        })
    if (run_dir / "derived" / "sync-latency-profile.json").exists():
        required.update({
            "derived/sync-latency-profile.json",
            "derived/sync-latency.json",
            "htapcheck/sync-latency.csv",
        })
    if (run_dir / "derived" / "workload-drift-profile.json").exists():
        required.update({
            "derived/workload-drift-profile.json",
            "derived/workload-drift-factor.json",
            "derived/query-feature-map.json",
            "derived/query-feature-dist.before.json",
            "derived/query-feature-dist.after.json",
            "derived/query-drift-sample.sql",
        })
    if (run_dir / "derived" / "data-drift-profile.json").exists() or (run_dir / "derived" / "data-drift-factor.json").exists():
        required.update({
            "derived/data-drift-profile.json",
            "derived/data-drift-factor.json",
            "derived/drift-plan.json",
        })
    if (run_dir / "derived" / "chaos-profile.json").exists():
        required.update({
            "derived/chaos-profile.json",
            "derived/cleanup-policy.json",
            "derived/cleanup-report.json",
            "derived/target-selector.resolved.json",
        })
    tp_profile_env = load_env(run_dir / "derived" / "tp-profile.env")
    capabilities = load_json(run_dir / "observability" / "timeline" / "capabilities.json")
    if (run_dir / "derived" / "mixed-baseline.json").exists():
        required.add("validation/plot-status.json")
        if first_non_empty(tp_profile_env.get("AUTO_RENDER_PLOTS"), default="true") != "false":
            required.update({
                "figures/plot-manifest.json",
                "figures/run-overview.png",
                "figures/run-panels.png",
            })
    if capabilities.get("session_memory_observation") == "supported":
        required.update({
            "observability/system_stats_memory.csv",
            "observability/system_stats_backend_memory.csv",
        })
    if capabilities.get("kcache_observation") == "supported":
        required.update({
            "observability/pg_stat_kcache.csv",
            "observability/timeline/kcache-metrics.csv",
        })
    return sorted(required)


def main() -> None:
    args = parse_args()
    run_dir = Path(args.run_dir)
    validation_dir = run_dir / "validation"
    explainability_dir = run_dir / "explainability"
    report_dir = run_dir / "report"
    validation_dir.mkdir(parents=True, exist_ok=True)
    explainability_dir.mkdir(parents=True, exist_ok=True)
    report_dir.mkdir(parents=True, exist_ok=True)

    properties = build_properties(run_dir)
    properties_path = report_dir / "run.properties.effective"
    properties_path.write_text(
        "".join(f"{key}={shell_value(value)}\n" for key, value in sorted(properties.items())),
        encoding="utf-8",
    )

    provisional_artifacts = collect_artifacts(run_dir, [], "report/run.properties.effective", "report/report-manifest.json")
    (explainability_dir / "event-timeline.md").write_text(
        "# event timeline\n\n" + "\n".join(f"- observed artifact: {entry['path']}" for entry in provisional_artifacts if entry.get("exists")),
        encoding="utf-8",
    )
    (explainability_dir / "top-findings.md").write_text(
        "# top findings\n\n- explainability bundle generated from current run artifacts\n",
        encoding="utf-8",
    )
    (validation_dir / "explainability.json").write_text(
        json.dumps(
            {
                "artifacts": [entry["path"] for entry in provisional_artifacts if entry.get("exists")],
                "report_manifest": "report/report-manifest.json",
                "report_properties": "report/run.properties.effective",
                "status": "draft",
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )

    required_artifacts = build_required_artifacts(run_dir)
    properties["report_bundle_required_count"] = str(len(required_artifacts))
    artifact_entries: dict[str, dict[str, object]] = {}
    for rel_path in ROOT_REQUIRED_FILES:
        add_entry(artifact_entries, run_dir, rel_path, "root", required=True)
    for directory in DIRECTORIES_TO_INDEX:
        directory_path = run_dir / directory
        if not directory_path.exists():
            continue
        for path in sorted(directory_path.rglob("*")):
            if path.is_file():
                add_entry(artifact_entries, run_dir, path.relative_to(run_dir).as_posix(), directory, required=False)
    add_entry(artifact_entries, run_dir, "report/run.properties.effective", "report", required=True, exists=True)
    add_entry(artifact_entries, run_dir, "report/report-manifest.json", "report", required=True, exists=True)
    for rel_path in required_artifacts:
        add_entry(artifact_entries, run_dir, rel_path, "report", required=True)

    artifacts = sorted(artifact_entries.values(), key=lambda item: str(item["path"]))
    missing_required = [entry["path"] for entry in artifacts if entry.get("required") and not entry.get("exists")]
    bundle_status = "complete" if not missing_required else "missing-required-artifacts"
    properties["report_bundle_status"] = bundle_status
    properties["report_bundle_missing_count"] = str(len(missing_required))
    properties["report_bundle_required_count"] = str(len(required_artifacts))
    properties_path.write_text(
        "".join(f"{key}={shell_value(value)}\n" for key, value in sorted(properties.items())),
        encoding="utf-8",
    )

    report_manifest = {
        "version": 1,
        "generated_by": "60_explainability_bundle.py",
        "run_dir": ".",
        "status": bundle_status,
        "run_properties_effective": "report/run.properties.effective",
        "required_artifacts": required_artifacts,
        "missing_required_artifacts": missing_required,
        "artifacts": artifacts,
    }
    (report_dir / "report-manifest.json").write_text(json.dumps(report_manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    (explainability_dir / "event-timeline.md").write_text(
        "# event timeline\n\n" + "\n".join(f"- observed artifact: {entry['path']}" for entry in artifacts if entry.get("exists")),
        encoding="utf-8",
    )
    (explainability_dir / "top-findings.md").write_text(
        "# top findings\n\n- explainability bundle generated from current run artifacts\n",
        encoding="utf-8",
    )
    (validation_dir / "explainability.json").write_text(
        json.dumps(
            {
                "artifacts": [entry["path"] for entry in artifacts if entry.get("exists")],
                "report_manifest": "report/report-manifest.json",
                "report_properties": "report/run.properties.effective",
                "status": bundle_status,
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
