#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Finalize TP progress and summary artifacts")
    parser.add_argument("--driver", required=True)
    parser.add_argument("--log-file", required=True)
    parser.add_argument("--progress-file", required=True)
    parser.add_argument("--summary-file", required=True)
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def write_progress(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=["elapsed_seconds", "tps", "latency_ms", "source"])
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def parse_pgbench_progress(log_path: Path) -> list[dict[str, Any]]:
    if not log_path.exists():
        return []
    pattern = re.compile(
        r"progress:\s*([0-9.]+)\s*s,\s*([0-9.]+)\s*tps(?:,|\s).*?(?:lat|latency)\s*(?:avg\s*=\s*|)([0-9.]+)\s*ms",
        re.IGNORECASE,
    )
    rows: list[dict[str, Any]] = []
    for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = pattern.search(line)
        if not match:
            continue
        rows.append(
            {
                "elapsed_seconds": f"{float(match.group(1)):.3f}",
                "tps": f"{float(match.group(2)):.6f}",
                "latency_ms": f"{float(match.group(3)):.6f}",
                "source": "pgbench",
            }
        )
    return rows


def parse_pgbench_summary(log_path: Path) -> dict[str, Any]:
    if not log_path.exists():
        return {}
    text = log_path.read_text(encoding="utf-8", errors="replace")
    summary: dict[str, Any] = {}
    tps_matches = re.findall(r"tps = ([0-9.]+)", text)
    if tps_matches:
        summary["tp_tps"] = float(tps_matches[-1])
    latency_matches = re.findall(r"latency average = ([0-9.]+) ms", text)
    if latency_matches:
        summary["tp_latency_avg_ms"] = float(latency_matches[-1])
    txn_matches = re.findall(r"number of transactions actually processed: ([0-9]+)", text)
    if txn_matches:
        summary["tp_transactions"] = int(txn_matches[-1])
    return summary


def parse_sysbench_summary(log_path: Path) -> dict[str, Any]:
    if not log_path.exists():
        return {}
    text = log_path.read_text(encoding="utf-8", errors="replace")
    summary: dict[str, Any] = {}
    txn_matches = re.findall(r"transactions:\s*([0-9]+)\s*\(([0-9.]+) per sec\.\)", text, re.IGNORECASE)
    if txn_matches:
        transactions, tps = txn_matches[-1]
        summary["tp_transactions"] = int(transactions)
        summary["tp_tps"] = float(tps)
    latency_matches = re.findall(r"avg:\s*([0-9.]+)", text, re.IGNORECASE)
    if latency_matches:
        summary["tp_latency_avg_ms"] = float(latency_matches[-1])
    return summary


def main() -> None:
    args = parse_args()
    driver = args.driver.strip().lower()
    log_path = Path(args.log_file).expanduser().resolve()
    progress_path = Path(args.progress_file).expanduser().resolve()
    summary_path = Path(args.summary_file).expanduser().resolve()

    existing_summary = load_json(summary_path)
    if driver == "pgbench":
        progress_rows = parse_pgbench_progress(log_path)
        write_progress(progress_path, progress_rows)
        parsed_summary = parse_pgbench_summary(log_path)
    elif driver == "sysbench":
        parsed_summary = parse_sysbench_summary(log_path)
        if not progress_path.exists():
            write_progress(progress_path, [])
    else:
        raise SystemExit(f"unsupported TP driver: {driver}")

    summary = dict(existing_summary)
    summary.update(parsed_summary)
    summary["driver"] = driver
    summary["log_file"] = log_path.as_posix()
    summary["progress_file"] = progress_path.as_posix()
    summary["status"] = "completed"
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
