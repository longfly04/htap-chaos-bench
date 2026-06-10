#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from phase5_evidence_summary import collect_run_record


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Render comparison figures across mixed runs")
    parser.add_argument("--run-dir", action="append", default=[])
    parser.add_argument("--runlist")
    parser.add_argument("--output-dir", required=True)
    return parser.parse_args()


def resolve_run_dirs(args: argparse.Namespace) -> list[Path]:
    seen: set[Path] = set()
    run_dirs: list[Path] = []

    def add(raw: str) -> None:
        path = Path(raw).expanduser().resolve()
        if not path.exists() or path in seen:
            return
        seen.add(path)
        run_dirs.append(path)

    for raw in args.run_dir:
        add(raw)
    if args.runlist:
        for raw_line in Path(args.runlist).expanduser().read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            add(line)
    return run_dirs


def to_float(value: Any, default: float = 0.0) -> float:
    if value in (None, ""):
        return default
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def clamp01(value: float) -> float:
    return max(0.0, min(1.0, value))


def group_label(record: dict[str, Any]) -> str:
    for key in ("chaos_primitive", "htap_check_type", "variant", "rq"):
        value = str(record.get(key, "")).strip()
        if value and value not in {"none", "unknown", "not-requested"}:
            return value
    return "runs"


def save_figure(fig, path: Path, dpi: int, generated: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, dpi=dpi, bbox_inches="tight")
    generated.append(path.as_posix())


def build_radar_group(records: list[dict[str, Any]]) -> dict[str, list[float]]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for record in records:
        grouped.setdefault(group_label(record), []).append(record)

    radar: dict[str, list[float]] = {}
    for label, rows in grouped.items():
        tp_values = [to_float(row.get("tp_tps")) for row in rows if row.get("tp_tps") not in (None, "")]
        latency_values = [to_float(row.get("tp_latency_avg_ms")) for row in rows if row.get("tp_latency_avg_ms") not in (None, "")]
        drift_values = [to_float(row.get("workload_drift_realized_factor")) for row in rows if row.get("workload_drift_realized_factor") not in (None, "")]
        deadlock_values = [to_float(row.get("deadlock_detected_count")) for row in rows]
        wait_values = [to_float(row.get("wait_duration_ms")) for row in rows]
        spill_values = [to_float(row.get("spill_temp_bytes_delta")) for row in rows]
        sync_values = [to_float(row.get("sync_post_ms")) for row in rows]
        freshness_values = [to_float(row.get("freshness_latest_lag_ms")) for row in rows]

        throughput_loss = 0.0
        if tp_values and max(tp_values) > 0:
            throughput_loss = 1.0 - (min(tp_values) / max(tp_values))
        latency_inflation = 0.0
        if latency_values and min(latency_values) > 0:
            latency_inflation = (max(latency_values) - min(latency_values)) / min(latency_values)

        radar[label] = [
            clamp01(throughput_loss),
            clamp01(latency_inflation / 3.0),
            clamp01((max(spill_values) if spill_values else 0.0) / (1024 ** 3)),
            clamp01(max(deadlock_values + wait_values + [0.0]) / 5.0),
            clamp01(max(sync_values + freshness_values + [0.0]) / 5000.0),
            clamp01(max(drift_values + [0.0])),
        ]
    return radar


def main() -> None:
    args = parse_args()
    run_dirs = resolve_run_dirs(args)
    if not run_dirs:
        raise SystemExit("no run directories provided")

    try:
        import matplotlib.pyplot as plt
        import seaborn as sns
    except ImportError as exc:
        raise SystemExit(f"missing plotting dependency: {exc}")

    sns.set_theme(style="whitegrid")
    output_dir = Path(args.output_dir).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    records = [collect_run_record(run_dir) for run_dir in run_dirs]
    for record in records:
        record["group_label"] = group_label(record)

    generated: list[str] = []
    dpi = 300

    throughput_fig, throughput_ax = plt.subplots(figsize=(12, 7))
    ordered_groups = sorted({record["group_label"] for record in records})
    throughput_groups: list[str] = []
    throughput_data: list[list[float]] = []
    for label in ordered_groups:
        values = [to_float(record.get("tp_tps")) for record in records if record["group_label"] == label and record.get("tp_tps") not in (None, "")]
        if values:
            throughput_groups.append(label)
            throughput_data.append(values)
    throughput_ax.boxplot(throughput_data, labels=throughput_groups, patch_artist=True)
    for idx, label in enumerate(throughput_groups, start=1):
        values = [to_float(record.get("tp_tps")) for record in records if record["group_label"] == label and record.get("tp_tps") not in (None, "")]
        throughput_ax.scatter([idx] * len(values), values, color="black", alpha=0.55, s=25)
    throughput_ax.set_title("TP throughput by run group")
    throughput_ax.set_xlabel("group")
    throughput_ax.set_ylabel("tp_tps")
    throughput_ax.tick_params(axis="x", rotation=20)
    save_figure(throughput_fig, output_dir / "throughput-boxplot.png", dpi, generated)
    save_figure(throughput_fig, output_dir / "throughput-boxplot.pdf", dpi, generated)
    plt.close(throughput_fig)

    latency_fig, latency_ax = plt.subplots(figsize=(12, 7))
    latency_groups: list[str] = []
    latency_data: list[list[float]] = []
    for label in ordered_groups:
        values = [to_float(record.get("tp_latency_avg_ms")) for record in records if record["group_label"] == label and record.get("tp_latency_avg_ms") not in (None, "")]
        if values:
            latency_groups.append(label)
            latency_data.append(values)
    latency_ax.boxplot(latency_data, labels=latency_groups, patch_artist=True)
    for idx, label in enumerate(latency_groups, start=1):
        values = [to_float(record.get("tp_latency_avg_ms")) for record in records if record["group_label"] == label and record.get("tp_latency_avg_ms") not in (None, "")]
        latency_ax.scatter([idx] * len(values), values, color="black", alpha=0.55, s=25)
    latency_ax.set_title("TP latency by run group")
    latency_ax.set_xlabel("group")
    latency_ax.set_ylabel("tp_latency_avg_ms")
    latency_ax.tick_params(axis="x", rotation=20)
    save_figure(latency_fig, output_dir / "latency-boxplot.png", dpi, generated)
    save_figure(latency_fig, output_dir / "latency-boxplot.pdf", dpi, generated)
    plt.close(latency_fig)

    scatter_fig, scatter_ax = plt.subplots(figsize=(11, 7))
    palette = sns.color_palette("tab10", n_colors=max(3, len({record['group_label'] for record in records})))
    label_to_color = {label: palette[idx % len(palette)] for idx, label in enumerate(sorted({record['group_label'] for record in records}))}
    for record in records:
        scatter_ax.scatter(
            to_float(record.get("workload_drift_realized_factor")),
            to_float(record.get("tp_tps")),
            color=label_to_color[record["group_label"]],
            label=record["group_label"],
            alpha=0.75,
            s=70,
        )
    handles, labels = scatter_ax.get_legend_handles_labels()
    dedup: dict[str, Any] = {}
    for handle, label in zip(handles, labels):
        dedup.setdefault(label, handle)
    scatter_ax.legend(dedup.values(), dedup.keys(), loc="best")
    scatter_ax.set_title("Workload drift vs TP throughput")
    scatter_ax.set_xlabel("workload_drift_realized_factor")
    scatter_ax.set_ylabel("tp_tps")
    save_figure(scatter_fig, output_dir / "drift-vs-tps-scatter.png", dpi, generated)
    save_figure(scatter_fig, output_dir / "drift-vs-tps-scatter.pdf", dpi, generated)
    plt.close(scatter_fig)

    radar_values = build_radar_group(records)
    radar_labels = [
        "throughput_loss",
        "latency_inflation",
        "temp_io",
        "lock_wait",
        "htap_lag",
        "workload_drift",
    ]
    radar_fig = plt.figure(figsize=(10, 9))
    radar_ax = radar_fig.add_subplot(111, projection="polar")
    import math

    angles = [idx / float(len(radar_labels)) * 2 * math.pi for idx in range(len(radar_labels))]
    angles += angles[:1]
    for label, values in sorted(radar_values.items()):
        series = values + values[:1]
        radar_ax.plot(angles, series, linewidth=2, label=label)
        radar_ax.fill(angles, series, alpha=0.15)
    radar_ax.set_xticks(angles[:-1])
    radar_ax.set_xticklabels(radar_labels)
    radar_ax.set_yticklabels([])
    radar_ax.set_title("Chaos / HTAP impact radar by group")
    radar_ax.legend(loc="upper right", bbox_to_anchor=(1.25, 1.1))
    save_figure(radar_fig, output_dir / "chaos-radar.png", dpi, generated)
    save_figure(radar_fig, output_dir / "chaos-radar.pdf", dpi, generated)
    plt.close(radar_fig)

    manifest = {
        "status": "completed",
        "run_count": len(records),
        "generated_files": generated,
        "groups": sorted({record["group_label"] for record in records}),
    }
    (output_dir / "compare-manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
