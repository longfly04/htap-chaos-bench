#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import math
import re
import sys
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Render observability figures for a mixed run")
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--output-dir")
    parser.add_argument("--tp-log")
    parser.add_argument("--ap-events")
    parser.add_argument("--chaos-events")
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def load_csv_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open(encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    rows: list[dict[str, Any]] = []
    for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            rows.append(value)
    return rows


def to_float(value: Any, default: float = 0.0) -> float:
    if value in (None, ""):
        return default
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def to_int(value: Any, default: int = 0) -> int:
    if value in (None, ""):
        return default
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return default


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def write_status(path: Path, payload: dict[str, Any]) -> None:
    ensure_parent(path)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def detect_start_epoch_ms(system_rows: list[dict[str, str]], ap_events: list[dict[str, Any]], chaos_events: list[dict[str, Any]]) -> int:
    candidates: list[int] = []
    for row in system_rows[:1]:
        ts = to_int(row.get("ts_epoch_ms"))
        if ts > 0:
            candidates.append(ts)
    for rows in (ap_events[:1], chaos_events[:1]):
        for row in rows:
            ts = to_int(row.get("ts_epoch_ms"))
            if ts > 0:
                candidates.append(ts)
    return min(candidates) if candidates else 0


def parse_tp_progress(tp_progress_path: Path, tp_log_path: Path) -> list[dict[str, float]]:
    if tp_progress_path.exists():
        rows: list[dict[str, float]] = []
        for row in load_csv_rows(tp_progress_path):
            rows.append(
                {
                    "elapsed_seconds": to_float(row.get("elapsed_seconds")),
                    "tps": to_float(row.get("tps")),
                    "latency_ms": to_float(row.get("latency_ms")),
                }
            )
        return rows
    if not tp_log_path.exists():
        return []
    pattern = re.compile(
        r"progress:\s*([0-9.]+)\s*s,\s*([0-9.]+)\s*tps(?:,|\s).*?(?:lat|latency)\s*(?:avg\s*=\s*|)([0-9.]+)\s*ms",
        re.IGNORECASE,
    )
    rows: list[dict[str, float]] = []
    for line in tp_log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = pattern.search(line)
        if not match:
            continue
        rows.append(
            {
                "elapsed_seconds": float(match.group(1)),
                "tps": float(match.group(2)),
                "latency_ms": float(match.group(3)),
            }
        )
    return rows


def derive_delta_series(rows: list[dict[str, str]], value_key: str) -> tuple[list[float], list[float]]:
    xs: list[float] = []
    ys: list[float] = []
    previous_value: float | None = None
    previous_t: float | None = None
    for row in rows:
        current_t = to_float(row.get("elapsed_seconds"))
        current_value = to_float(row.get(value_key))
        if previous_value is None or previous_t is None or current_t <= previous_t:
            previous_value = current_value
            previous_t = current_t
            continue
        xs.append(current_t)
        ys.append((current_value - previous_value) / max(current_t - previous_t, 1e-6))
        previous_value = current_value
        previous_t = current_t
    return xs, ys


def derive_cumulative_delta(rows: list[dict[str, str]], value_key: str, scale: float = 1.0) -> tuple[list[float], list[float]]:
    xs: list[float] = []
    ys: list[float] = []
    if not rows:
        return xs, ys
    baseline = to_float(rows[0].get(value_key))
    for row in rows:
        xs.append(to_float(row.get("elapsed_seconds")))
        ys.append((to_float(row.get(value_key)) - baseline) / scale)
    return xs, ys


def derive_ap_rate(ap_events: list[dict[str, Any]], start_epoch_ms: int) -> tuple[list[float], list[float], int]:
    buckets: dict[int, int] = {}
    completed = 0
    for row in ap_events:
        if row.get("status") != "completed":
            continue
        ts = to_int(row.get("ts_epoch_ms"))
        if ts <= 0 or start_epoch_ms <= 0:
            continue
        bucket = max(int((ts - start_epoch_ms) / 1000), 0)
        buckets[bucket] = buckets.get(bucket, 0) + 1
        completed += 1
    xs = sorted(float(bucket) for bucket in buckets.keys())
    ys = [float(buckets[int(bucket)]) for bucket in xs]
    return xs, ys, completed


def format_chaos_label(event: str, index: int) -> str:
    pretty_event = event.replace("_", " ").replace("-", " ").strip()
    return f"chaos_t{index + 1}: {pretty_event}"


def build_chaos_markers(chaos_events: list[dict[str, Any]], start_epoch_ms: int) -> list[dict[str, Any]]:
    palette = ["#d62728", "#ff7f0e", "#9467bd", "#8c564b", "#17becf"]
    markers: list[dict[str, Any]] = []
    ordered_events = sorted(chaos_events, key=lambda row: to_int(row.get("ts_epoch_ms")))
    for index, row in enumerate(ordered_events):
        ts = to_int(row.get("ts_epoch_ms"))
        event = str(row.get("event", "")).strip()
        if ts <= 0 or start_epoch_ms <= 0 or not event:
            continue
        seconds = max((ts - start_epoch_ms) / 1000.0, 0.0)
        markers.append(
            {
                "seconds": seconds,
                "event": event,
                "color": palette[index % len(palette)],
                "legend_label": format_chaos_label(event, index),
            }
        )
    return markers


def clamp01(value: float) -> float:
    return max(0.0, min(1.0, value))


def build_radar_values(summary: dict[str, Any], activity_rows: list[dict[str, str]]) -> dict[str, float]:
    throughput_values = [to_float(row.get("tps")) for row in summary.get("tp_progress", []) if to_float(row.get("tps")) > 0]
    latency_values = [to_float(row.get("latency_ms")) for row in summary.get("tp_progress", []) if to_float(row.get("latency_ms")) > 0]
    max_blocked = max((to_float(row.get("blocked_sessions")) for row in activity_rows), default=0.0)
    freshness_lag = to_float(summary.get("freshness", {}).get("latest_lag_ms_post_mix"))
    sync_lag = to_float(summary.get("sync_latency", {}).get("post_mix_sync_latency_ms"))
    drift_factor = to_float(summary.get("workload_drift", {}).get("realized_workload_factor"))
    temp_bytes_delta = to_float(summary.get("spill", {}).get("temp_bytes_delta"))
    wait_duration_ms = to_float(summary.get("waitxact", {}).get("wait_duration_ms"))
    deadlock_count = to_float(summary.get("deadlock", {}).get("deadlock_detected_count"))

    throughput_loss = 0.0
    if len(throughput_values) >= 2 and max(throughput_values) > 0:
        throughput_loss = 1.0 - (min(throughput_values) / max(throughput_values))
    latency_inflation = 0.0
    if latency_values:
        baseline = min(latency_values)
        peak = max(latency_values)
        if baseline > 0:
            latency_inflation = (peak - baseline) / baseline

    return {
        "throughput_loss": clamp01(throughput_loss),
        "latency_inflation": clamp01(latency_inflation / 3.0),
        "temp_io": clamp01(temp_bytes_delta / (1024 ** 3)),
        "lock_wait": clamp01(max(max_blocked, wait_duration_ms / 1000.0, deadlock_count) / 5.0),
        "htap_lag": clamp01(max(freshness_lag, sync_lag) / 5000.0),
        "workload_drift": clamp01(drift_factor),
    }


def save_figure(fig, path: Path, dpi: int, generated_files: list[str]) -> None:
    ensure_parent(path)
    fig.savefig(path, dpi=dpi, bbox_inches="tight")
    generated_files.append(path.as_posix())


def add_panel_notice(axis, title: str, message: str) -> None:
    axis.set_title(title)
    axis.set_xlabel("elapsed seconds")
    axis.text(0.5, 0.5, message, transform=axis.transAxes, ha="center", va="center", fontsize=11, color="#666666")


def main() -> None:
    args = parse_args()
    run_dir = Path(args.run_dir).expanduser().resolve()
    output_dir = Path(args.output_dir).expanduser().resolve() if args.output_dir else (run_dir / "figures")
    panels_dir = output_dir / "panels"
    status_path = run_dir / "validation" / "plot-status.json"
    manifest_path = output_dir / "plot-manifest.json"

    system_metrics_path = run_dir / "observability" / "timeline" / "system-metrics.csv"
    activity_metrics_path = run_dir / "observability" / "timeline" / "activity-metrics.csv"
    statement_metrics_path = run_dir / "observability" / "timeline" / "statement-metrics.csv"
    io_metrics_path = run_dir / "observability" / "timeline" / "io-metrics.csv"
    wait_metrics_path = run_dir / "observability" / "timeline" / "wait-metrics.csv"
    memory_metrics_path = run_dir / "observability" / "timeline" / "memory-metrics.csv"
    kcache_metrics_path = run_dir / "observability" / "timeline" / "kcache-metrics.csv"
    capabilities_path = run_dir / "observability" / "timeline" / "capabilities.json"
    tp_log_path = Path(args.tp_log).expanduser().resolve() if args.tp_log else (run_dir / "tp" / "freshness-updates.log")
    tp_progress_path = run_dir / "tp" / "progress.csv"
    ap_events_path = Path(args.ap_events).expanduser().resolve() if args.ap_events else (run_dir / "observability" / "timeline" / "ap-events.jsonl")
    chaos_events_path = Path(args.chaos_events).expanduser().resolve() if args.chaos_events else (run_dir / "derived" / "chaos-events.jsonl")

    missing_inputs = [
        path.as_posix()
        for path in [system_metrics_path, activity_metrics_path, tp_log_path]
        if not path.exists()
    ]
    if missing_inputs:
        write_status(
            status_path,
            {
                "status": "failed",
                "error": "missing required plotting inputs",
                "missing_inputs": missing_inputs,
                "generated_files": [],
            },
        )
        raise SystemExit(1)

    try:
        import matplotlib.pyplot as plt
        import seaborn as sns
        from matplotlib.lines import Line2D
    except ImportError as exc:
        write_status(
            status_path,
            {
                "status": "skipped-env-missing",
                "error": f"missing plotting dependency: {exc}",
                "missing_inputs": [],
                "generated_files": [],
            },
        )
        raise SystemExit(0)

    sns.set_theme(style="whitegrid")

    system_rows = load_csv_rows(system_metrics_path)
    activity_rows = load_csv_rows(activity_metrics_path)
    statement_rows = load_csv_rows(statement_metrics_path)
    io_rows = load_csv_rows(io_metrics_path)
    wait_rows = load_csv_rows(wait_metrics_path)
    memory_rows = load_csv_rows(memory_metrics_path)
    kcache_rows = load_csv_rows(kcache_metrics_path)
    capabilities = load_json(capabilities_path)
    ap_events = load_jsonl(ap_events_path)
    chaos_events = load_jsonl(chaos_events_path)
    tp_progress = parse_tp_progress(tp_progress_path, tp_log_path)
    freshness = load_json(run_dir / "derived" / "freshness-check.json")
    sync_latency = load_json(run_dir / "derived" / "sync-latency.json")
    workload_drift = load_json(run_dir / "derived" / "workload-drift-factor.json")
    waitxact = load_json(run_dir / "derived" / "waitxact-chaos.json")
    deadlock = load_json(run_dir / "derived" / "deadlock-pair-chaos.json")
    spill = load_json(run_dir / "derived" / "spill-pressure-chaos.json")
    summary_json = load_json(run_dir / "summary.json")
    metadata = load_json(run_dir / "observability" / "timeline" / "plot-metadata.json")
    dpi = max(to_int(metadata.get("plot_dpi"), 300), 150)

    start_epoch_ms = detect_start_epoch_ms(system_rows, ap_events, chaos_events)
    chaos_markers = build_chaos_markers(chaos_events, start_epoch_ms)
    qps_x, qps_y = derive_delta_series(statement_rows, "total_calls")
    stmt_temp_x, stmt_temp_y = derive_delta_series(statement_rows, "temp_blks_written")
    sample_tps_x, sample_tps_y = derive_delta_series(system_rows, "xact_commit")
    temp_x, temp_y = derive_cumulative_delta(system_rows, "temp_bytes", scale=1024 ** 2)
    blocked_x = [to_float(row.get("elapsed_seconds")) for row in activity_rows]
    blocked_y = [to_float(row.get("blocked_sessions")) for row in activity_rows]
    wait_y = [to_float(row.get("waiting_sessions")) for row in activity_rows]
    lock_wait_y = [to_float(row.get("lock_wait_sessions")) for row in activity_rows]
    io_wait_y = [to_float(row.get("io_wait_sessions")) for row in activity_rows]
    lwlock_wait_y = [to_float(row.get("lwlock_wait_sessions")) for row in activity_rows]
    tp_progress_x = [row["elapsed_seconds"] for row in tp_progress]
    tp_tps_y = [row["tps"] for row in tp_progress]
    tp_latency_y = [row["latency_ms"] for row in tp_progress]
    ap_x, ap_y, ap_completed = derive_ap_rate(ap_events, start_epoch_ms)
    wait_profile_x, wait_profile_total_y = derive_delta_series(wait_rows, "total_wait_samples")
    _, wait_profile_lock_y = derive_delta_series(wait_rows, "lock_wait_samples")
    _, wait_profile_lwlock_y = derive_delta_series(wait_rows, "lwlock_wait_samples")
    _, wait_profile_io_y = derive_delta_series(wait_rows, "io_wait_samples")
    kcache_reads_x, kcache_reads_y = derive_delta_series(kcache_rows, "exec_reads_blks")
    _, kcache_writes_y = derive_delta_series(kcache_rows, "exec_writes_blks")
    _, kcache_user_cpu_y = derive_delta_series(kcache_rows, "exec_user_time_seconds")
    _, kcache_system_cpu_y = derive_delta_series(kcache_rows, "exec_system_time_seconds")
    memory_x = [to_float(row.get("elapsed_seconds")) for row in memory_rows]
    db_cached_mb_y = [to_float(row.get("db_cached_mb")) for row in memory_rows]
    db_dirty_mb_y = [to_float(row.get("db_dirty_mb")) for row in memory_rows]
    system_used_mb_y = [to_float(row.get("system_used_mb")) for row in memory_rows]
    system_cache_mb_y = [to_float(row.get("system_cache_mb")) for row in memory_rows]
    pg_all_backend_mb_y = [to_float(row.get("pg_all_backend_mb")) for row in memory_rows]
    pg_client_backend_mb_y = [to_float(row.get("pg_client_backend_mb")) for row in memory_rows]
    tp_backend_mb_y = [to_float(row.get("tp_backend_mb")) for row in memory_rows]
    ap_backend_mb_y = [to_float(row.get("ap_backend_mb")) for row in memory_rows]
    chaos_backend_mb_y = [to_float(row.get("chaos_backend_mb")) for row in memory_rows]
    other_backend_mb_y = [to_float(row.get("other_backend_mb")) for row in memory_rows]
    sampler_memory_used_y = [to_float(row.get("sampler_backend_used_mb")) for row in memory_rows]

    generated_files: list[str] = []
    warnings: list[str] = []
    if not tp_progress:
        warnings.append("TP progress rows were not parsed; throughput panel falls back to sampled xact deltas")
    if capabilities.get("wait_sampling_observation") != "supported":
        warnings.append("pg_wait_sampling timeline unavailable; wait-event profile falls back to pg_stat_activity-derived signals")
    if capabilities.get("buffer_cache_observation") != "supported":
        warnings.append("pg_buffercache unavailable; buffer-cache time series are omitted")
    if capabilities.get("session_memory_observation") == "sampler-backend-only":
        warnings.append("session memory currently reflects only the sampler backend, not all benchmark sessions")
    elif capabilities.get("session_memory_observation") != "supported":
        warnings.append("session memory observation is unavailable in the current runtime")
    if capabilities.get("kcache_observation") != "supported":
        warnings.append("pg_stat_kcache is unavailable; kernel CPU/read/write overlays are omitted")

    overview_fig, overview_axes = plt.subplots(3, 1, figsize=(18, 14), sharex=True)
    throughput_ax, latency_ax, io_ax = overview_axes
    if tp_progress:
        throughput_ax.plot(tp_progress_x, tp_tps_y, label="tp_tps", color="#1f77b4", linewidth=2)
    if sample_tps_x:
        throughput_ax.plot(sample_tps_x, sample_tps_y, label="sampled_tps_est", color="#2ca02c", linewidth=1.8, linestyle="--")
    if qps_x:
        throughput_ax.plot(qps_x, qps_y, label="qps_est", color="#ff7f0e", linewidth=1.6)
    if ap_x:
        throughput_ax.plot(ap_x, ap_y, label="ap_rounds_per_sec", color="#9467bd", linewidth=1.6)
    throughput_ax.set_ylabel("throughput / rate")
    throughput_ax.set_title(f"Run overview: {summary_json.get('run_name', run_dir.name)}")

    if tp_progress:
        latency_ax.plot(tp_progress_x, tp_latency_y, label="tp_latency_ms", color="#d62728", linewidth=2)
    latency_ax.plot(blocked_x, blocked_y, label="blocked_sessions", color="#8c564b", linewidth=1.7)
    latency_ax.plot(blocked_x, wait_y, label="waiting_sessions", color="#17becf", linewidth=1.7)
    latency_ax.set_ylabel("latency / sessions")

    latency_handles, latency_labels = latency_ax.get_legend_handles_labels()
    if wait_profile_x:
        latency_wait_ax = latency_ax.twinx()
        latency_wait_ax.plot(wait_profile_x, wait_profile_total_y, label="wait_profile_total_per_s", color="#7f7f7f", linewidth=1.4, linestyle="--")
        latency_wait_ax.plot(wait_profile_x, wait_profile_lock_y, label="wait_profile_lock_per_s", color="#bc5090", linewidth=1.3, linestyle=":")
        latency_wait_ax.plot(wait_profile_x, wait_profile_io_y, label="wait_profile_io_per_s", color="#ffa600", linewidth=1.3, linestyle=":")
        latency_wait_ax.set_ylabel("wait samples / s")
        wait_handles, wait_labels = latency_wait_ax.get_legend_handles_labels()
        latency_ax.legend(latency_handles + wait_handles, latency_labels + wait_labels, loc="upper right")
    else:
        latency_ax.legend(loc="upper right")

    io_ax.plot(temp_x, temp_y, label="temp_bytes_delta_mb", color="#bcbd22", linewidth=2)
    if stmt_temp_x:
        io_ax.plot(stmt_temp_x, stmt_temp_y, label="temp_blks_written_per_s", color="#7f7f7f", linewidth=1.6)
    if memory_x:
        io_ax.plot(memory_x, db_cached_mb_y, label="db_cached_mb", color="#1f77b4", linewidth=1.5, linestyle="--")
        io_ax.plot(memory_x, db_dirty_mb_y, label="db_dirty_mb", color="#d62728", linewidth=1.4, linestyle=":")
        if capabilities.get("session_memory_observation") == "supported" and any(value > 0 for value in pg_client_backend_mb_y):
            io_ax.plot(memory_x, pg_client_backend_mb_y, label="pg_client_backend_mb", color="#17becf", linewidth=1.4, linestyle="-.")
            if any(value > 0 for value in chaos_backend_mb_y):
                io_ax.plot(memory_x, chaos_backend_mb_y, label="chaos_backend_mb", color="#9467bd", linewidth=1.2, linestyle=":")
        elif any(value > 0 for value in sampler_memory_used_y):
            io_ax.plot(memory_x, sampler_memory_used_y, label="sampler_backend_used_mb", color="#17becf", linewidth=1.3, linestyle="-.")
    io_ax.set_ylabel("temp / memory (MB)")
    io_ax.set_xlabel("elapsed seconds")
    io_ax.legend(loc="upper right")

    for axis in overview_axes:
        for marker in chaos_markers:
            axis.axvline(marker["seconds"], color=marker["color"], linestyle="--", linewidth=1.5, alpha=0.9)

    throughput_handles, throughput_labels = throughput_ax.get_legend_handles_labels()
    chaos_handles = [
        Line2D([0], [0], color=marker["color"], linestyle="--", linewidth=1.5, label=marker["legend_label"])
        for marker in chaos_markers
    ]
    throughput_ax.legend(
        throughput_handles + chaos_handles,
        throughput_labels + [marker["legend_label"] for marker in chaos_markers],
        loc="upper right",
    )

    panels_fig, panels_axes = plt.subplots(3, 2, figsize=(18, 16))
    panel_tp = panels_axes[0, 0]
    panel_activity = panels_axes[0, 1]
    panel_io = panels_axes[1, 0]
    panel_wait = panels_axes[1, 1]
    panel_memory = panels_axes[2, 0]
    panel_radar = panels_axes[2, 1]

    if tp_progress:
        panel_tp.plot(tp_progress_x, tp_tps_y, color="#1f77b4", linewidth=2, label="tp_tps")
        panel_tp_twin = panel_tp.twinx()
        panel_tp_twin.plot(tp_progress_x, tp_latency_y, color="#d62728", linewidth=1.7, label="tp_latency_ms")
        panel_tp.set_title("TP throughput and latency")
        panel_tp.set_xlabel("elapsed seconds")
        panel_tp.set_ylabel("tps")
        panel_tp_twin.set_ylabel("latency ms")
    else:
        panel_tp.plot(sample_tps_x, sample_tps_y, color="#2ca02c", linewidth=2, label="sampled_tps_est")
        panel_tp.set_title("Sampled TPS estimate")
        panel_tp.set_xlabel("elapsed seconds")
        panel_tp.set_ylabel("tps")

    panel_activity.plot(blocked_x, blocked_y, color="#8c564b", linewidth=1.8, label="blocked_sessions")
    panel_activity.plot(blocked_x, wait_y, color="#17becf", linewidth=1.8, label="waiting_sessions")
    panel_activity.plot(blocked_x, lock_wait_y, color="#bc5090", linewidth=1.4, linestyle="--", label="lock_wait_sessions")
    panel_activity.plot(blocked_x, io_wait_y, color="#ffa600", linewidth=1.4, linestyle="--", label="io_wait_sessions")
    panel_activity.plot(blocked_x, [to_float(row.get("tp_sessions")) for row in activity_rows], color="#1f77b4", linewidth=1.3, linestyle="--", label="tp_sessions")
    panel_activity.plot(blocked_x, [to_float(row.get("ap_sessions")) for row in activity_rows], color="#9467bd", linewidth=1.3, linestyle="--", label="ap_sessions")
    panel_activity.set_title("Activity / waits")
    panel_activity.set_xlabel("elapsed seconds")
    panel_activity.legend(loc="upper right")

    panel_io.plot(temp_x, temp_y, color="#bcbd22", linewidth=2, label="temp_bytes_delta_mb")
    if qps_x:
        panel_io.plot(qps_x, qps_y, color="#ff7f0e", linewidth=1.6, label="qps_est")
    if stmt_temp_x:
        panel_io.plot(stmt_temp_x, stmt_temp_y, color="#7f7f7f", linewidth=1.4, linestyle="--", label="temp_blks_written_per_s")
    if kcache_reads_x:
        panel_io.plot(kcache_reads_x, kcache_reads_y, color="#1f77b4", linewidth=1.3, linestyle=":", label="kcache_reads_blks_per_s")
        panel_io.plot(kcache_reads_x, kcache_writes_y, color="#d62728", linewidth=1.3, linestyle=":", label="kcache_writes_blks_per_s")
    panel_io.set_title("Temp I/O and statement rate")
    panel_io.set_xlabel("elapsed seconds")
    panel_io.legend(loc="upper left")

    if wait_profile_x:
        panel_wait.plot(wait_profile_x, wait_profile_total_y, color="#7f7f7f", linewidth=1.8, label="total_wait_samples_per_s")
        panel_wait.plot(wait_profile_x, wait_profile_lock_y, color="#bc5090", linewidth=1.5, linestyle="--", label="lock_wait_samples_per_s")
        panel_wait.plot(wait_profile_x, wait_profile_lwlock_y, color="#58508d", linewidth=1.5, linestyle="--", label="lwlock_wait_samples_per_s")
        panel_wait.plot(wait_profile_x, wait_profile_io_y, color="#ffa600", linewidth=1.5, linestyle="--", label="io_wait_samples_per_s")
        panel_wait.set_title("pg_wait_sampling profile")
        panel_wait.set_xlabel("elapsed seconds")
        panel_wait.legend(loc="upper right")
    else:
        add_panel_notice(panel_wait, "pg_wait_sampling profile", "Extension unavailable in current runtime; using pg_stat_activity waits in other panels.")

    if memory_x:
        panel_memory.plot(memory_x, db_cached_mb_y, color="#1f77b4", linewidth=1.8, label="db_cached_mb")
        panel_memory.plot(memory_x, db_dirty_mb_y, color="#d62728", linewidth=1.5, linestyle="--", label="db_dirty_mb")
        panel_memory.set_xlabel("elapsed seconds")
        panel_memory.set_ylabel("MB")
        if capabilities.get("session_memory_observation") == "supported" and any(value > 0 for value in pg_all_backend_mb_y):
            panel_memory.plot(memory_x, pg_client_backend_mb_y, color="#17becf", linewidth=1.6, label="pg_client_backend_mb")
            panel_memory.plot(memory_x, tp_backend_mb_y, color="#2ca02c", linewidth=1.3, linestyle="-.", label="tp_backend_mb")
            panel_memory.plot(memory_x, ap_backend_mb_y, color="#9467bd", linewidth=1.3, linestyle="-.", label="ap_backend_mb")
            if any(value > 0 for value in chaos_backend_mb_y):
                panel_memory.plot(memory_x, chaos_backend_mb_y, color="#8c564b", linewidth=1.3, linestyle=":", label="chaos_backend_mb")
            if any(value > 0 for value in other_backend_mb_y):
                panel_memory.plot(memory_x, other_backend_mb_y, color="#7f7f7f", linewidth=1.2, linestyle=":", label="other_backend_mb")
            panel_memory.set_title("Buffer cache / backend memory")
            memory_handles, memory_labels = panel_memory.get_legend_handles_labels()
            if any(value > 0 for value in system_used_mb_y) or any(value > 0 for value in system_cache_mb_y):
                panel_memory_twin = panel_memory.twinx()
                panel_memory_twin.plot(memory_x, [value / 1024.0 for value in system_used_mb_y], color="#bcbd22", linewidth=1.2, label="system_used_gb")
                panel_memory_twin.plot(memory_x, [value / 1024.0 for value in system_cache_mb_y], color="#ff9896", linewidth=1.2, linestyle="--", label="system_cache_gb")
                panel_memory_twin.set_ylabel("system memory (GB)")
                twin_handles, twin_labels = panel_memory_twin.get_legend_handles_labels()
                panel_memory.legend(memory_handles + twin_handles, memory_labels + twin_labels, loc="upper right")
            else:
                panel_memory.legend(loc="upper right")
        else:
            if any(value > 0 for value in sampler_memory_used_y):
                panel_memory.plot(memory_x, sampler_memory_used_y, color="#17becf", linewidth=1.4, linestyle="-.", label="sampler_backend_used_mb")
            panel_memory.set_title("Buffer cache / sampler memory")
            panel_memory.legend(loc="upper right")
    else:
        add_panel_notice(panel_memory, "Buffer cache / backend memory", "Memory observability unavailable in current runtime.")

    radar_values = build_radar_values(
        {
            "tp_progress": tp_progress,
            "freshness": freshness,
            "sync_latency": sync_latency,
            "workload_drift": workload_drift,
            "spill": spill,
            "waitxact": waitxact,
            "deadlock": deadlock,
        },
        activity_rows,
    )
    radar_labels = list(radar_values.keys())
    radar_scores = list(radar_values.values())
    angles = [idx / float(len(radar_labels)) * 2 * math.pi for idx in range(len(radar_labels))]
    angles += angles[:1]
    radar_scores += radar_scores[:1]
    panel_radar.remove()
    panel_radar = panels_fig.add_subplot(3, 2, 6, projection="polar")
    panel_radar.plot(angles, radar_scores, color="#1f77b4", linewidth=2)
    panel_radar.fill(angles, radar_scores, color="#1f77b4", alpha=0.2)
    panel_radar.set_xticks(angles[:-1])
    panel_radar.set_xticklabels(radar_labels)
    panel_radar.set_yticklabels([])
    panel_radar.set_title("Impact radar")

    panels_fig.suptitle(f"Run panels: {summary_json.get('run_id', run_dir.name)} | AP rounds={ap_completed}")
    overview_fig.tight_layout()
    panels_fig.tight_layout(rect=[0, 0, 1, 0.97])

    save_figure(overview_fig, output_dir / "run-overview.png", dpi, generated_files)
    save_figure(overview_fig, output_dir / "run-overview.pdf", dpi, generated_files)
    save_figure(panels_fig, output_dir / "run-panels.png", dpi, generated_files)
    save_figure(panels_fig, output_dir / "run-panels.pdf", dpi, generated_files)
    save_figure(overview_fig, panels_dir / "throughput-and-chaos.png", dpi, generated_files)
    save_figure(panels_fig, panels_dir / "impact-panels.png", dpi, generated_files)

    plt.close(overview_fig)
    plt.close(panels_fig)

    manifest = {
        "status": "completed",
        "run_dir": run_dir.as_posix(),
        "generated_files": generated_files,
        "warnings": warnings,
        "inputs": {
            "system_metrics": system_metrics_path.as_posix(),
            "activity_metrics": activity_metrics_path.as_posix(),
            "statement_metrics": statement_metrics_path.as_posix(),
            "io_metrics": io_metrics_path.as_posix(),
            "wait_metrics": wait_metrics_path.as_posix(),
            "memory_metrics": memory_metrics_path.as_posix(),
            "kcache_metrics": kcache_metrics_path.as_posix(),
            "capabilities": capabilities_path.as_posix(),
            "tp_progress": tp_progress_path.as_posix(),
            "tp_log": tp_log_path.as_posix(),
            "ap_events": ap_events_path.as_posix(),
            "chaos_events": chaos_events_path.as_posix(),
        },
        "plot_profile": metadata.get("plot_profile", "mixed-default"),
        "plot_dpi": dpi,
        "chaos_marker_count": len(chaos_markers),
    }
    ensure_parent(manifest_path)
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    write_status(
        status_path,
        {
            "status": "completed",
            "generated_files": generated_files,
            "warnings": warnings,
            "missing_inputs": [],
            "plot_manifest": manifest_path.as_posix(),
        },
    )


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:  # pragma: no cover - best-effort runtime artifact
        if len(sys.argv) > 2 and sys.argv[1] == "--run-dir":
            run_dir = Path(sys.argv[2]).expanduser().resolve()
            write_status(
                run_dir / "validation" / "plot-status.json",
                {
                    "status": "failed",
                    "error": str(exc),
                    "generated_files": [],
                    "missing_inputs": [],
                },
            )
        raise
