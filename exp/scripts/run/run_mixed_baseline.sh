#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
EXP_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$EXP_ROOT/.." && pwd)"
# shellcheck disable=SC1090
source "$PROJECT_ROOT/config/project-paths.env"
source "${HARNESS_COMMON:-$PROJECT_ROOT/scripts/harness_common.sh}"
# shellcheck disable=SC1090
source "$EXP_ROOT/scripts/job_config.sh"
job_load_runtime_config "$EXP_ROOT"

RUN_DIR="${1:-}"
[[ -n "$RUN_DIR" ]] || { echo "run directory is required" >&2; exit 1; }
mkdir -p "$RUN_DIR/validation" "$RUN_DIR/derived" "$RUN_DIR/explainability" "$RUN_DIR/tp" "$RUN_DIR/ap" "$RUN_DIR/lock" "$RUN_DIR/chaos" "$RUN_DIR/htapcheck" "$RUN_DIR/observability/timeline" "$RUN_DIR/figures"

OBSERVE_PHASE_FILE="$RUN_DIR/observability/timeline/current-phase.txt"
OBSERVE_LIFECYCLE_FILE="$RUN_DIR/observability/timeline/lifecycle-phases.json"
OBSERVE_LIFECYCLE_EVENTS_FILE="$RUN_DIR/observability/timeline/lifecycle-events.jsonl"
PHASE_PRE_INJECTION="pre-injection"
PHASE_DURING_INJECTION="during-injection"
PHASE_POST_INJECTION="post-injection"
TP_PID=""
AP_PIDS=()
CHAOS_PIDS=()
OBSERVABILITY_SAMPLER_PID=""
OBSERVABILITY_STARTED_EPOCH_MS="0"
OBSERVE_BOUNDARY_PG_ACTIVITY_INDEX="0"
START_PSQL_SESSION_PID=""
TP_SQL_FILE_USED=""
AP_QUERY_FILE_USED=""
TP_THREADS_USED=""
TP_TERMINALS_USED=""
TP_RATE_CAP_USED=""
TP_DRIVER_USED=""
TP_LOG_FILE_USED=""
TP_PROGRESS_FILE_USED=""
TP_SUMMARY_FILE_USED=""
TP_SYSBENCH_SCRIPT_USED=""
AP_TERMINALS_USED=""
WORKLOAD_OVERLAP_USED=""
AP_BURST_INTERVAL_USED=""
AP_TOTAL_ROUNDS="0"
TP_RUNTIME_SECONDS_USED="0"
AP_RUNTIME_SECONDS_USED="0"
HTAP_CHECK_TYPE_USED="${HTAP_CHECK_TYPE:-none}"
FRESHNESS_PROBE_ID_USED="${FRESHNESS_PROBE_ID:-}"
FRESHNESS_QUERY_CLASS_USED="${FRESHNESS_QUERY_CLASS:-${AP_CLASS:-na}}"
FRESHNESS_TARGET_RANGE_USED="${FRESHNESS_TARGET_RANGE:-}"
FRESHNESS_STATUS_USED="not-requested"
FRESHNESS_SAMPLE_COUNT="0"
FRESHNESS_MAX_EPOCH_DELTA="0"
FRESHNESS_POST_LATEST_LAG_MS="0"
SYNC_LATENCY_PROBE_ID_USED="${SYNC_LATENCY_PROBE_ID:-}"
SYNC_LATENCY_QUERY_CLASS_USED="${SYNC_LATENCY_QUERY_CLASS:-${AP_CLASS:-na}}"
SYNC_LATENCY_TARGET_RANGE_USED="${SYNC_LATENCY_TARGET_RANGE:-}"
SYNC_LATENCY_TARGET_MOVIE_ID_USED=""
SYNC_LATENCY_STATUS_USED="not-requested"
SYNC_LATENCY_SAMPLE_COUNT="0"
SYNC_LATENCY_MAX_LATENCY_MS="0"
SYNC_LATENCY_POST_LATENCY_MS="0"
WORKLOAD_DRIFT_ENABLED_USED="${WORKLOAD_DRIFT_ENABLED:-false}"
WORKLOAD_DRIFT_FACTOR_USED="${WORKLOAD_DRIFT_FACTOR:-0}"
WORKLOAD_DRIFT_REALIZED_FACTOR_USED="${WORKLOAD_DRIFT_REALIZED_FACTOR:-0}"
WORKLOAD_DRIFT_BASE_CLASS_USED="${WORKLOAD_DRIFT_BASE_CLASS:-${AP_CLASS:-na}}"
WORKLOAD_DRIFT_SAMPLE_SIZE_USED="${WORKLOAD_DRIFT_SAMPLE_SIZE:-0}"
WORKLOAD_DRIFT_STATUS_USED="${WORKLOAD_DRIFT_STATUS:-not-requested}"
CHAOS_PRIMITIVE_USED="${CHAOS_PRIMITIVE:-none}"
CHAOS_STAGE_USED="${CHAOS_STAGE:-}"
CHAOS_TARGET_SELECTOR_USED="${CHAOS_TARGET_SELECTOR:-}"
CHAOS_INTENSITY_USED="${CHAOS_INTENSITY:-}"
CHAOS_STATUS_USED="not-requested"
CHAOS_WAIT_JOBS_USED="0"
CHAOS_LOCK_HOLD_SECONDS_USED="0"
CHAOS_FIXTURE_USED="false"
CHAOS_START_AFTER_SECONDS_USED="0"
CHAOS_DURATION_SECONDS_USED="0"
CHAOS_TARGET_MOVIE_ID=""
CHAOS_WAIT_DURATION_MS="0"
CHAOS_WAITER_FAILURE_COUNT="0"
CHAOS_TOTAL_WAITER_COUNT="0"
CHAOS_BLOCKER_EXIT_CODE="0"
CHAOS_DEADLOCK_JOBS_USED="0"
CHAOS_DEADLOCK_ROW_1_ID=""
CHAOS_DEADLOCK_ROW_2_ID=""
CHAOS_DEADLOCK_ABORT_COUNT="0"
CHAOS_DEADLOCK_COMMIT_COUNT="0"
CHAOS_DEADLOCK_DETECTED_COUNT="0"
CHAOS_DEADLOCK_SESSION_FAILURE_COUNT="0"
CHAOS_DEADLOCK_ELAPSED_MS="0"
CHAOS_WORKERS_USED="0"
CHAOS_SESSION_MEMORY_USED=""
CHAOS_RATE_USED="0"
CHAOS_SPILL_QUERY_CLASS_USED=""
CHAOS_SPILL_QUERY_FILE_USED=""
CHAOS_SPILL_WORKER_FAILURE_COUNT="0"
CHAOS_SPILL_TOTAL_ROUNDS="0"
CHAOS_SPILL_TEMP_FILES_BEFORE="0"
CHAOS_SPILL_TEMP_FILES_AFTER="0"
CHAOS_SPILL_TEMP_FILES_DELTA="0"
CHAOS_SPILL_TEMP_BYTES_BEFORE="0"
CHAOS_SPILL_TEMP_BYTES_AFTER="0"
CHAOS_SPILL_TEMP_BYTES_DELTA="0"
CHAOS_SPILL_EXECUTION_RATE_QPS="0"
CHAOS_SPILL_ELAPSED_MS="0"

cleanup_background() {
  local status=$?
  if [[ -n "$TP_PID" ]] && kill -0 "$TP_PID" 2>/dev/null; then
    kill "$TP_PID" 2>/dev/null || true
  fi
  for pid in "${AP_PIDS[@]:-}"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done
  for pid in "${CHAOS_PIDS[@]:-}"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done
  if [[ -n "$OBSERVABILITY_SAMPLER_PID" ]] && kill -0 "$OBSERVABILITY_SAMPLER_PID" 2>/dev/null; then
    kill "$OBSERVABILITY_SAMPLER_PID" 2>/dev/null || true
    wait "$OBSERVABILITY_SAMPLER_PID" 2>/dev/null || true
  fi
  return "$status"
}
trap cleanup_background EXIT

threads_for_pressure() {
  job_tp_threads_for_pressure "${TP_PRESSURE:-medium}"
}

resolve_ap_query_for_class() {
  job_ap_query_file_for_class "$EXP_ROOT" "$1"
}

resolve_ap_query() {
  if workload_drift_enabled; then
    local drift_query_file="${JOB_WORKLOAD_DRIFT_QUERY_FILE:-}"
    [[ -n "$drift_query_file" ]] || fail "workload drift query sample is not set"
    [[ -f "$drift_query_file" ]] || fail "workload drift query sample does not exist: $drift_query_file"
    printf '%s\n' "$drift_query_file"
    return
  fi
  resolve_ap_query_for_class "${AP_CLASS:-sort-heavy}"
}

htap_check_enabled() {
  [[ "${HTAP_CHECK_ENABLED:-false}" == "true" && "${HTAP_CHECK_TYPE:-none}" == "query-oriented" ]]
}

workload_drift_enabled() {
  [[ "${WORKLOAD_DRIFT_ENABLED:-false}" == "true" && -n "${JOB_WORKLOAD_DRIFT_QUERY_FILE:-}" ]]
}

set_observability_phase() {
  printf '%s\n' "$1" > "$OBSERVE_PHASE_FILE"
}

append_lifecycle_event() {
  local phase="$1"
  local event="$2"
  printf '{"ts_epoch_ms":%s,"phase":"%s","event":"%s"}\n' \
    "$(date +%s%3N)" \
    "$phase" \
    "$event" >> "$OBSERVE_LIFECYCLE_EVENTS_FILE"
}

write_lifecycle_descriptor() {
  cat > "$OBSERVE_LIFECYCLE_FILE" <<EOF
{
  "pre_injection_phase": "$PHASE_PRE_INJECTION",
  "during_injection_phase": "$PHASE_DURING_INJECTION",
  "post_injection_phase": "$PHASE_POST_INJECTION",
  "overlap_mode": "${WORKLOAD_OVERLAP_USED:-${WORKLOAD_OVERLAP:-${OVERLAP:-tp-first}}}",
  "chaos_mode": "${CHAOS_MODE:-none}",
  "warmup_seconds": ${WARMUP_SECONDS:-0},
  "duration_seconds": ${DURATION_SECONDS:-60},
  "measure_seconds": ${MEASURE_SECONDS:-${DURATION_SECONDS:-60}}
}
EOF
}

observability_elapsed_seconds() {
  local now_epoch_ms="$1"
  ${PYTHON_BIN:-python} - "$OBSERVABILITY_STARTED_EPOCH_MS" "$now_epoch_ms" <<'PY'
import sys
start = int(sys.argv[1])
now = int(sys.argv[2])
print(f"{max(now - start, 0) / 1000.0:.3f}")
PY
}

capture_pg_activity_boundary_snapshot() {
  local phase="$1"
  local sample_label="$2"
  local ts_epoch_ms elapsed_seconds sample_index

  if [[ "${OBSERVE_PG_ACTIVITY_ENABLED:-false}" != "true" ]]; then
    return 0
  fi

  ts_epoch_ms="$(date +%s%3N)"
  if [[ "$OBSERVABILITY_STARTED_EPOCH_MS" =~ ^[0-9]+$ ]] && (( OBSERVABILITY_STARTED_EPOCH_MS > 0 )); then
    elapsed_seconds="$(observability_elapsed_seconds "$ts_epoch_ms")"
  else
    elapsed_seconds="0.000"
  fi
  sample_index=$((1000000 + OBSERVE_BOUNDARY_PG_ACTIVITY_INDEX))
  OBSERVE_BOUNDARY_PG_ACTIVITY_INDEX=$((OBSERVE_BOUNDARY_PG_ACTIVITY_INDEX + 1))

  capture_pg_activity_timeline_snapshot "$RUN_DIR" "$sample_index" "$ts_epoch_ms" "$elapsed_seconds" "$phase" "boundary-${sample_label}" "${BENCHMARK_DB_NAME:-${JOB_DB_NAME:?missing JOB_DB_NAME}}" "${DB_SUPERUSER:-postgres}" "${DB_SUPERUSER_PASSWORD:-postgres}"
}

capture_lifecycle_boundary() {
  local phase="$1"
  local sample_label="${2:-$1}"
  local event_label="${3:-$sample_label}"
  set_observability_phase "$phase"
  append_lifecycle_event "$phase" "$event_label"
  capture_pg_activity_boundary_snapshot "$phase" "$sample_label"
  capture_freshness_sample "$sample_label"
  capture_sync_latency_sample "$sample_label"
}

append_ap_event() {
  local event="$1"
  local worker_id="$2"
  local round="$3"
  local status="${4:-}"
  local duration_ms="${5:-0}"
  local log_file="${6:-}"
  printf '{"ts_epoch_ms":%s,"event":"%s","worker_id":%s,"round":%s,"status":"%s","duration_ms":%s,"log_file":"%s"}\n' \
    "$(date +%s%3N)" \
    "$event" \
    "$worker_id" \
    "$round" \
    "$status" \
    "$duration_ms" \
    "$log_file" >> "$RUN_DIR/observability/timeline/ap-events.jsonl"
}

start_observability_sampler() {
  if [[ "${EXPORT_PG_STATS:-true}" != "true" ]]; then
    return 0
  fi
  if [[ -n "$OBSERVABILITY_SAMPLER_PID" ]] && kill -0 "$OBSERVABILITY_SAMPLER_PID" 2>/dev/null; then
    return 0
  fi
  OBSERVABILITY_STARTED_EPOCH_MS="$(date +%s%3N)"
  OBSERVE_BOUNDARY_PG_ACTIVITY_INDEX="0"
  set_observability_phase "$PHASE_PRE_INJECTION"
  "${HARNESS_SAMPLE_PG_STATS:-$PROJECT_ROOT/scripts/harness_sample_pg_stats.sh}" \
    --run-dir "$RUN_DIR" \
    --database "${BENCHMARK_DB_NAME:-${JOB_DB_NAME:?missing JOB_DB_NAME}}" \
    --interval-seconds "${OBSERVE_SAMPLING_INTERVAL_SECONDS:-5}" \
    --phase-file "$OBSERVE_PHASE_FILE" &
  OBSERVABILITY_SAMPLER_PID="$!"
}

stop_observability_sampler() {
  if [[ -n "$OBSERVABILITY_SAMPLER_PID" ]] && kill -0 "$OBSERVABILITY_SAMPLER_PID" 2>/dev/null; then
    kill "$OBSERVABILITY_SAMPLER_PID" 2>/dev/null || true
    wait "$OBSERVABILITY_SAMPLER_PID" 2>/dev/null || true
  fi
  OBSERVABILITY_SAMPLER_PID=""
}

capture_freshness_sample() {
  local phase="$1"
  local sql_file="${JOB_FRESHNESS_PROBE_SQL_FILE:-}"
  local sample_file="$RUN_DIR/htapcheck/freshness-${phase}.csv"
  local aggregate_file="$RUN_DIR/htapcheck/freshness.csv"
  local database="${BENCHMARK_DB_NAME:-${JOB_DB_NAME:?missing JOB_DB_NAME}}"
  local pg_user="${AP_USER:-${BENCH_USER:-${DB_SUPERUSER:-postgres}}}"
  local pg_password="${AP_PASSWORD:-${BENCH_PASSWORD:-${DB_SUPERUSER_PASSWORD:-postgres}}}"

  htap_check_enabled || return 0
  [[ -n "$sql_file" ]] || fail "query-oriented freshness probe SQL file is not set"

  if is_source_runtime; then
    PGPASSWORD="$pg_password" \
      "$(source_pg_bin_dir)/psql" \
      -h "$(source_pg_host)" \
      -p "$(source_pg_port)" \
      -U "$pg_user" \
      -d "$database" \
      --csv \
      --set "probe_id=${FRESHNESS_PROBE_ID_USED:-job-tp-hotspot-freshness}" \
      --set "query_class=${FRESHNESS_QUERY_CLASS_USED:-${AP_CLASS:-na}}" \
      --set "probe_phase=$phase" \
      --set "hot_modulus=${JOB_TP_HOT_MODULUS:?missing JOB_TP_HOT_MODULUS}" \
      --set "hot_remainder=${JOB_TP_HOT_REMAINDER:?missing JOB_TP_HOT_REMAINDER}" \
      -f "$(workspace_to_host_path "$sql_file")" > "$sample_file"
  else
    compose exec -T \
      -e PGPASSWORD="$pg_password" \
      "${DB_SERVICE_NAME:-postgres}" \
      psql -h 127.0.0.1 -U "$pg_user" -d "$database" \
      --csv \
      --set "probe_id=${FRESHNESS_PROBE_ID_USED:-job-tp-hotspot-freshness}" \
      --set "query_class=${FRESHNESS_QUERY_CLASS_USED:-${AP_CLASS:-na}}" \
      --set "probe_phase=$phase" \
      --set "hot_modulus=${JOB_TP_HOT_MODULUS:?missing JOB_TP_HOT_MODULUS}" \
      --set "hot_remainder=${JOB_TP_HOT_REMAINDER:?missing JOB_TP_HOT_REMAINDER}" \
      -f "$sql_file" > "$sample_file"
  fi

  if [[ ! -f "$aggregate_file" ]]; then
    cp "$sample_file" "$aggregate_file"
  else
    tail -n +2 "$sample_file" >> "$aggregate_file"
  fi
  FRESHNESS_SAMPLE_COUNT="$(( FRESHNESS_SAMPLE_COUNT + 1 ))"
  FRESHNESS_STATUS_USED="captured"
}

write_freshness_artifacts() {
  local aggregate_file="$RUN_DIR/htapcheck/freshness.csv"
  local summary_file="$RUN_DIR/derived/freshness-check.json"
  local env_file="$RUN_DIR/derived/freshness-check.env"

  htap_check_enabled || return 0
  [[ -f "$aggregate_file" ]] || fail "query-oriented freshness samples are missing: $aggregate_file"

  "${PYTHON_BIN:-python}" - "$aggregate_file" "$summary_file" "$env_file" <<'PY'
import csv
import json
import sys
from pathlib import Path

csv_path = Path(sys.argv[1])
summary_path = Path(sys.argv[2])
env_path = Path(sys.argv[3])
rows = list(csv.DictReader(csv_path.open(encoding="utf-8")))
if not rows:
    raise SystemExit(f"freshness csv is empty: {csv_path}")

def to_int(value):
    return int(value or 0)

first = rows[0]
last = rows[-1]
summary = {
    "probe_id": last.get("probe_id", ""),
    "query_class": last.get("query_class", ""),
    "target_range": last.get("target_range", ""),
    "sample_count": len(rows),
    "phases": [row.get("probe_phase", "") for row in rows],
    "touched_rows_pre_mix": to_int(first.get("touched_rows")),
    "touched_rows_post_mix": to_int(last.get("touched_rows")),
    "max_epoch_pre_mix": to_int(first.get("max_epoch")),
    "max_epoch_post_mix": to_int(last.get("max_epoch")),
    "max_epoch_delta": to_int(last.get("max_epoch")) - to_int(first.get("max_epoch")),
    "latest_lag_ms_post_mix": to_int(last.get("latest_lag_ms")),
    "latest_touch_ts_post_mix": last.get("latest_touch_ts", ""),
    "status": "completed" if len(rows) >= 2 else "partial",
    "samples": [
        {
            "probe_phase": row.get("probe_phase", ""),
            "touched_rows": to_int(row.get("touched_rows")),
            "min_epoch": to_int(row.get("min_epoch")),
            "max_epoch": to_int(row.get("max_epoch")),
            "latest_lag_ms": to_int(row.get("latest_lag_ms")),
            "latest_touch_ts": row.get("latest_touch_ts", ""),
        }
        for row in rows
    ],
}
summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
env_path.write_text(
    "\n".join(
        [
            f"FRESHNESS_SAMPLE_COUNT={summary['sample_count']}",
            f"FRESHNESS_MAX_EPOCH_DELTA={summary['max_epoch_delta']}",
            f"FRESHNESS_POST_LATEST_LAG_MS={summary['latest_lag_ms_post_mix']}",
            f"FRESHNESS_STATUS={summary['status']}",
        ]
    )
    + "\n",
    encoding="utf-8",
)
PY

  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
  FRESHNESS_SAMPLE_COUNT="${FRESHNESS_SAMPLE_COUNT:-0}"
  FRESHNESS_MAX_EPOCH_DELTA="${FRESHNESS_MAX_EPOCH_DELTA:-0}"
  FRESHNESS_POST_LATEST_LAG_MS="${FRESHNESS_POST_LATEST_LAG_MS:-0}"
  FRESHNESS_STATUS_USED="${FRESHNESS_STATUS:-captured}"
}

sync_latency_check_enabled() {
  [[ "${HTAP_CHECK_ENABLED:-false}" == "true" && "${HTAP_CHECK_TYPE:-none}" == "sync-latency" ]]
}

capture_sync_latency_sample() {
  local phase="$1"
  local sql_file="${JOB_SYNC_LATENCY_PROBE_SQL_FILE:-}"
  local sample_file="$RUN_DIR/htapcheck/sync-latency-${phase}.csv"
  local aggregate_file="$RUN_DIR/htapcheck/sync-latency.csv"
  local update_file="$RUN_DIR/htapcheck/sync-latency-${phase}.update.csv"
  local observe_file="$RUN_DIR/htapcheck/sync-latency-${phase}.observe.csv"
  local update_env_file="$RUN_DIR/htapcheck/sync-latency-${phase}.update.env"
  local database="${BENCHMARK_DB_NAME:-${JOB_DB_NAME:?missing JOB_DB_NAME}}"
  local tp_user="${BENCH_USER:-${DB_SUPERUSER:-postgres}}"
  local tp_password="${BENCH_PASSWORD:-${DB_SUPERUSER_PASSWORD:-postgres}}"
  local obs_user="${AP_USER:-${BENCH_USER:-${DB_SUPERUSER:-postgres}}}"
  local obs_password="${AP_PASSWORD:-${BENCH_PASSWORD:-${DB_SUPERUSER_PASSWORD:-postgres}}}"
  local poll_interval_ms="${JOB_SYNC_LATENCY_POLL_INTERVAL_MS:?missing JOB_SYNC_LATENCY_POLL_INTERVAL_MS}"
  local timeout_ms="${JOB_SYNC_LATENCY_TIMEOUT_MS:?missing JOB_SYNC_LATENCY_TIMEOUT_MS}"
  local update_sql
  local target_movie_id=""
  local committed_epoch="0"
  local baseline_epoch="0"
  local commit_touch_ts=""
  local observed_epoch="0"
  local start_ms="0"
  local now_ms="0"
  local latency_ms="0"
  local poll_count=0
  local status="timeout"

  sync_latency_check_enabled || return 0
  [[ -n "$sql_file" ]] || fail "sync-latency probe SQL file is not set"

  read -r -d '' update_sql <<'SQL' || true
WITH target AS (
  SELECT movie_id, epoch AS baseline_epoch
  FROM movie_freshness
  WHERE movie_id % :hot_modulus = :hot_remainder
  ORDER BY movie_id ASC
  LIMIT 1
  FOR UPDATE
)
UPDATE movie_freshness mf
SET epoch = target.baseline_epoch + 1,
    last_touch_ts = clock_timestamp(),
    freshness_score = mf.freshness_score + 1
FROM target
WHERE mf.movie_id = target.movie_id
RETURNING mf.movie_id, target.baseline_epoch, mf.epoch AS committed_epoch, mf.last_touch_ts AS commit_touch_ts;
SQL

  if is_source_runtime; then
    printf '%s\n' "$update_sql" | \
      PGPASSWORD="$tp_password" \
      "$(source_pg_bin_dir)/psql" \
      -h "$(source_pg_host)" \
      -p "$(source_pg_port)" \
      -U "$tp_user" \
      -d "$database" \
      --csv \
      --set "hot_modulus=${JOB_TP_HOT_MODULUS:?missing JOB_TP_HOT_MODULUS}" \
      --set "hot_remainder=${JOB_TP_HOT_REMAINDER:?missing JOB_TP_HOT_REMAINDER}" > "$update_file"
  else
    printf '%s\n' "$update_sql" | \
      compose exec -T \
        -e PGPASSWORD="$tp_password" \
        "${DB_SERVICE_NAME:-postgres}" \
        psql -h 127.0.0.1 -U "$tp_user" -d "$database" \
        --csv \
        --set "hot_modulus=${JOB_TP_HOT_MODULUS:?missing JOB_TP_HOT_MODULUS}" \
        --set "hot_remainder=${JOB_TP_HOT_REMAINDER:?missing JOB_TP_HOT_REMAINDER}" > "$update_file"
  fi

  "${PYTHON_BIN:-python}" - "$update_file" "$update_env_file" <<'PY'
import csv
import shlex
import sys
from pathlib import Path

update_path = Path(sys.argv[1])
env_path = Path(sys.argv[2])
rows = list(csv.DictReader(update_path.open(encoding="utf-8")))
row = next((candidate for candidate in rows if (candidate.get("movie_id") or "").isdigit()), None)
if row is None:
    raise SystemExit(f"sync-latency update csv is empty: {update_path}")
env_lines = [
    f"SYNC_TARGET_MOVIE_ID={int(row.get('movie_id') or 0)}",
    f"SYNC_BASELINE_EPOCH={int(row.get('baseline_epoch') or 0)}",
    f"SYNC_COMMITTED_EPOCH={int(row.get('committed_epoch') or 0)}",
    f"SYNC_COMMIT_TOUCH_TS={shlex.quote(row.get('commit_touch_ts', ''))}",
]
env_path.write_text("\n".join(env_lines) + "\n", encoding="utf-8")
PY

  set -a
  # shellcheck disable=SC1090
  source "$update_env_file"
  set +a
  target_movie_id="${SYNC_TARGET_MOVIE_ID:-}"
  baseline_epoch="${SYNC_BASELINE_EPOCH:-0}"
  committed_epoch="${SYNC_COMMITTED_EPOCH:-0}"
  commit_touch_ts="${SYNC_COMMIT_TOUCH_TS:-}"
  [[ -n "$target_movie_id" ]] || fail "sync-latency target movie_id is missing"

  start_ms="$(date +%s%3N)"
  while :; do
    poll_count=$(( poll_count + 1 ))
    if is_source_runtime; then
      PGPASSWORD="$obs_password" \
        "$(source_pg_bin_dir)/psql" \
        -h "$(source_pg_host)" \
        -p "$(source_pg_port)" \
        -U "$obs_user" \
        -d "$database" \
        --csv \
        --set "probe_id=${SYNC_LATENCY_PROBE_ID_USED:-job-tp-hotspot-sync-latency}" \
        --set "query_class=${SYNC_LATENCY_QUERY_CLASS_USED:-${AP_CLASS:-na}}" \
        --set "probe_phase=$phase" \
        --set "target_movie_id=$target_movie_id" \
        -f "$(workspace_to_host_path "$sql_file")" > "$observe_file"
    else
      compose exec -T \
        -e PGPASSWORD="$obs_password" \
        "${DB_SERVICE_NAME:-postgres}" \
        psql -h 127.0.0.1 -U "$obs_user" -d "$database" \
        --csv \
        --set "probe_id=${SYNC_LATENCY_PROBE_ID_USED:-job-tp-hotspot-sync-latency}" \
        --set "query_class=${SYNC_LATENCY_QUERY_CLASS_USED:-${AP_CLASS:-na}}" \
        --set "probe_phase=$phase" \
        --set "target_movie_id=$target_movie_id" \
        -f "$sql_file" > "$observe_file"
    fi

    observed_epoch="$("${PYTHON_BIN:-python}" - "$observe_file" <<'PY'
import csv
import sys
from pathlib import Path
rows = list(csv.DictReader(Path(sys.argv[1]).open(encoding="utf-8")))
if not rows:
    raise SystemExit(f"sync-latency observe csv is empty: {sys.argv[1]}")
print(int(rows[-1].get("observed_epoch") or 0))
PY
)"
    now_ms="$(date +%s%3N)"
    if [[ "$observed_epoch" =~ ^[0-9]+$ ]] && (( observed_epoch >= committed_epoch )); then
      status="visible"
      break
    fi
    if (( now_ms - start_ms >= timeout_ms )); then
      break
    fi
    "${PYTHON_BIN:-python}" - "$poll_interval_ms" <<'PY'
import sys
import time

time.sleep(max(int(sys.argv[1]), 0) / 1000.0)
PY
  done

  latency_ms="$(( now_ms - start_ms ))"
  "${PYTHON_BIN:-python}" - "$update_file" "$observe_file" "$sample_file" "$phase" "$poll_count" "$latency_ms" "$status" "$SYNC_LATENCY_TARGET_RANGE_USED" <<'PY'
import csv
import sys
from pathlib import Path

update_path = Path(sys.argv[1])
observe_path = Path(sys.argv[2])
sample_path = Path(sys.argv[3])
phase = sys.argv[4]
poll_count = int(sys.argv[5])
latency_ms = int(sys.argv[6])
status = sys.argv[7]
target_range = sys.argv[8]
update_rows = list(csv.DictReader(update_path.open(encoding="utf-8")))
observe_rows = list(csv.DictReader(observe_path.open(encoding="utf-8")))
update_row = next((candidate for candidate in update_rows if (candidate.get("movie_id") or "").isdigit()), None)
if update_row is None:
    raise SystemExit(f"sync-latency update csv is empty: {update_path}")
if not observe_rows:
    raise SystemExit(f"sync-latency observe csv is empty: {observe_path}")
observe_row = observe_rows[-1]
fieldnames = [
    "probe_id",
    "query_class",
    "probe_phase",
    "target_range",
    "target_movie_id",
    "baseline_epoch",
    "committed_epoch",
    "observed_epoch",
    "commit_touch_ts",
    "observed_touch_ts",
    "observed_lag_ms",
    "poll_count",
    "sync_latency_ms",
    "status",
]
row = {
    "probe_id": observe_row.get("probe_id", ""),
    "query_class": observe_row.get("query_class", ""),
    "probe_phase": phase,
    "target_range": target_range,
    "target_movie_id": int(update_row.get("movie_id") or 0),
    "baseline_epoch": int(update_row.get("baseline_epoch") or 0),
    "committed_epoch": int(update_row.get("committed_epoch") or 0),
    "observed_epoch": int(observe_row.get("observed_epoch") or 0),
    "commit_touch_ts": update_row.get("commit_touch_ts", ""),
    "observed_touch_ts": observe_row.get("observed_touch_ts", ""),
    "observed_lag_ms": int(observe_row.get("observed_lag_ms") or 0),
    "poll_count": poll_count,
    "sync_latency_ms": latency_ms,
    "status": status,
}
with sample_path.open("w", encoding="utf-8", newline="") as fh:
    writer = csv.DictWriter(fh, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerow(row)
PY

  if [[ ! -f "$aggregate_file" ]]; then
    cp "$sample_file" "$aggregate_file"
  else
    tail -n +2 "$sample_file" >> "$aggregate_file"
  fi
  SYNC_LATENCY_SAMPLE_COUNT="$(( SYNC_LATENCY_SAMPLE_COUNT + 1 ))"
  if (( latency_ms > SYNC_LATENCY_MAX_LATENCY_MS )); then
    SYNC_LATENCY_MAX_LATENCY_MS="$latency_ms"
  fi
  if [[ "$phase" == post-injection* ]]; then
    SYNC_LATENCY_POST_LATENCY_MS="$latency_ms"
    SYNC_LATENCY_TARGET_MOVIE_ID_USED="$target_movie_id"
  fi
  SYNC_LATENCY_STATUS_USED="$status"
}

write_sync_latency_artifacts() {
  local aggregate_file="$RUN_DIR/htapcheck/sync-latency.csv"
  local summary_file="$RUN_DIR/derived/sync-latency.json"
  local env_file="$RUN_DIR/derived/sync-latency.env"

  sync_latency_check_enabled || return 0
  [[ -f "$aggregate_file" ]] || fail "sync-latency samples are missing: $aggregate_file"

  "${PYTHON_BIN:-python}" - "$aggregate_file" "$summary_file" "$env_file" <<'PY'
import csv
import json
import sys
from pathlib import Path

csv_path = Path(sys.argv[1])
summary_path = Path(sys.argv[2])
env_path = Path(sys.argv[3])
rows = list(csv.DictReader(csv_path.open(encoding="utf-8")))
if not rows:
    raise SystemExit(f"sync-latency csv is empty: {csv_path}")

def to_int(value):
    return int(value or 0)

last = rows[-1]
latencies = [to_int(row.get("sync_latency_ms")) for row in rows]
poll_counts = [to_int(row.get("poll_count")) for row in rows]
statuses = [row.get("status", "") for row in rows]
summary = {
    "probe_id": last.get("probe_id", ""),
    "query_class": last.get("query_class", ""),
    "target_range": last.get("target_range", ""),
    "target_movie_id": to_int(last.get("target_movie_id")),
    "sample_count": len(rows),
    "phases": [row.get("probe_phase", "") for row in rows],
    "max_sync_latency_ms": max(latencies) if latencies else 0,
    "post_mix_sync_latency_ms": to_int(last.get("sync_latency_ms")),
    "max_poll_count": max(poll_counts) if poll_counts else 0,
    "status": "completed" if rows and all(status == "visible" for status in statuses) else "partial",
    "samples": [
        {
            "probe_phase": row.get("probe_phase", ""),
            "target_movie_id": to_int(row.get("target_movie_id")),
            "baseline_epoch": to_int(row.get("baseline_epoch")),
            "committed_epoch": to_int(row.get("committed_epoch")),
            "observed_epoch": to_int(row.get("observed_epoch")),
            "sync_latency_ms": to_int(row.get("sync_latency_ms")),
            "poll_count": to_int(row.get("poll_count")),
            "commit_touch_ts": row.get("commit_touch_ts", ""),
            "observed_touch_ts": row.get("observed_touch_ts", ""),
            "observed_lag_ms": to_int(row.get("observed_lag_ms")),
            "status": row.get("status", ""),
        }
        for row in rows
    ],
}
summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
env_path.write_text(
    "\n".join(
        [
            f"SYNC_LATENCY_SAMPLE_COUNT={summary['sample_count']}",
            f"SYNC_LATENCY_MAX_MS={summary['max_sync_latency_ms']}",
            f"SYNC_LATENCY_POST_MS={summary['post_mix_sync_latency_ms']}",
            f"SYNC_LATENCY_TARGET_MOVIE_ID={summary['target_movie_id']}",
            f"SYNC_LATENCY_STATUS={summary['status']}",
        ]
    )
    + "\n",
    encoding="utf-8",
)
PY

  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
  SYNC_LATENCY_SAMPLE_COUNT="${SYNC_LATENCY_SAMPLE_COUNT:-0}"
  SYNC_LATENCY_MAX_LATENCY_MS="${SYNC_LATENCY_MAX_MS:-0}"
  SYNC_LATENCY_POST_LATENCY_MS="${SYNC_LATENCY_POST_MS:-0}"
  SYNC_LATENCY_TARGET_MOVIE_ID_USED="${SYNC_LATENCY_TARGET_MOVIE_ID:-}"
  SYNC_LATENCY_STATUS_USED="${SYNC_LATENCY_STATUS:-captured}"
}

prepare_tp_driver_settings() {
  local runtime_seconds="$1"
  TP_DRIVER_USED="${JOB_TP_DRIVER:-pgbench}"
  TP_DRIVER_USED="$(printf '%s' "$TP_DRIVER_USED" | tr '[:upper:]' '[:lower:]')"
  case "$TP_DRIVER_USED" in
    pgbench|sysbench)
      ;;
    *)
      echo "unsupported JOB_TP_DRIVER: $TP_DRIVER_USED" >&2
      exit 1
      ;;
  esac
  TP_THREADS_USED="${JOB_TP_THREADS:-$(threads_for_pressure)}"
  TP_TERMINALS_USED="${JOB_TP_TERMINALS:-$TP_THREADS_USED}"
  TP_RATE_CAP_USED="${JOB_TP_RATE_CAP:?missing JOB_TP_RATE_CAP}"
  TP_SQL_FILE_USED="${JOB_TP_SQL_FILE:?missing JOB_TP_SQL_FILE}"
  TP_RUNTIME_SECONDS_USED="$runtime_seconds"
  TP_LOG_FILE_USED="$RUN_DIR/tp/freshness-updates.log"
  TP_PROGRESS_FILE_USED="$RUN_DIR/tp/progress.csv"
  TP_SUMMARY_FILE_USED="$RUN_DIR/tp/summary.json"
  TP_SYSBENCH_SCRIPT_USED="${JOB_TP_SYSBENCH_SCRIPT:-$EXP_ROOT/scripts/run/tp_driver_sysbench.lua}"
}

finalize_tp_artifacts() {
  "${PYTHON_BIN:-python}" "$EXP_ROOT/scripts/run/finalize_tp_artifacts.py" \
    --driver "$TP_DRIVER_USED" \
    --log-file "$TP_LOG_FILE_USED" \
    --progress-file "$TP_PROGRESS_FILE_USED" \
    --summary-file "$TP_SUMMARY_FILE_USED"
}

start_psql_session() {
  local app_name="$1"
  local output_file="$2"
  local sql_body="$3"
  local database="${BENCHMARK_DB_NAME:-${JOB_DB_NAME:?missing JOB_DB_NAME}}"
  local pg_user="${LOCK_USER:-${DB_SUPERUSER:-postgres}}"
  local pg_password="${LOCK_PASSWORD:-${DB_SUPERUSER_PASSWORD:-postgres}}"

  if is_source_runtime; then
    printf '%s\n' "$sql_body" | \
      PGAPPNAME="$app_name" \
      PGPASSWORD="$pg_password" \
      "$(source_pg_bin_dir)/psql" \
      -h "$(source_pg_host)" \
      -p "$(source_pg_port)" \
      -U "$pg_user" \
      -d "$database" \
      -v ON_ERROR_STOP=1 > "$output_file" 2>&1 &
  else
    printf '%s\n' "$sql_body" | \
      compose exec -T \
        -e PGAPPNAME="$app_name" \
        -e PGPASSWORD="$pg_password" \
        "${DB_SERVICE_NAME:-postgres}" \
        psql -h 127.0.0.1 -U "$pg_user" -d "$database" -v ON_ERROR_STOP=1 > "$output_file" 2>&1 &
  fi
  START_PSQL_SESSION_PID="$!"
}

append_chaos_event() {
  local event="$1"
  local detail="${2:-}"
  printf '{"ts_epoch_ms":%s,"event":"%s","primitive":"%s","detail":"%s"}\n' \
    "$(date +%s%3N)" \
    "$event" \
    "${CHAOS_PRIMITIVE_USED:-none}" \
    "$detail" >> "$RUN_DIR/derived/chaos-events.jsonl"
}

resolve_lock_target_movie_id() {
  local modulus="${JOB_TP_HOT_MODULUS:?missing JOB_TP_HOT_MODULUS}"
  local remainder="${JOB_TP_HOT_REMAINDER:?missing JOB_TP_HOT_REMAINDER}"
  ensure_env_file
  run_psql "${BENCHMARK_DB_NAME:-${JOB_DB_NAME:?missing JOB_DB_NAME}}" "select movie_id from movie_freshness where movie_id % $modulus = $remainder order by last_touch_ts asc, movie_id asc limit 1"
}

resolve_deadlock_target_movie_ids() {
  local selector="${CHAOS_TARGET_SELECTOR:-fixture_rows:2}"
  local requested_rows="2"
  local modulus="${JOB_TP_HOT_MODULUS:?missing JOB_TP_HOT_MODULUS}"
  local remainder="${JOB_TP_HOT_REMAINDER:?missing JOB_TP_HOT_REMAINDER}"
  if [[ "$selector" == fixture_rows:* ]]; then
    requested_rows="${selector#fixture_rows:}"
  fi
  [[ "$requested_rows" =~ ^[0-9]+$ ]] || fail "deadlock_pair selector must be fixture_rows:<n>"
  if (( requested_rows != 2 )); then
    fail "deadlock_pair currently requires fixture_rows:2"
  fi
  ensure_env_file
  run_psql "${BENCHMARK_DB_NAME:-${JOB_DB_NAME:?missing JOB_DB_NAME}}" "select movie_id from movie_freshness where movie_id % $modulus = $remainder order by last_touch_ts asc, movie_id asc limit $requested_rows"
}

write_target_selector_resolved() {
  case "${CHAOS_PRIMITIVE_USED:-none}" in
    deadlock_pair)
      cat > "$RUN_DIR/derived/target-selector.resolved.json" <<EOF
{
  "primitive": "${CHAOS_PRIMITIVE_USED:-deadlock_pair}",
  "target_selector": "${CHAOS_TARGET_SELECTOR_USED:-fixture_rows:2}",
  "deadlock_jobs": "${CHAOS_DEADLOCK_JOBS_USED:-0}",
  "row_a_movie_id": "${CHAOS_DEADLOCK_ROW_1_ID:-}",
  "row_b_movie_id": "${CHAOS_DEADLOCK_ROW_2_ID:-}",
  "status": "resolved"
}
EOF
      ;;
    spill_pressure)
      cat > "$RUN_DIR/derived/target-selector.resolved.json" <<EOF
{
  "primitive": "${CHAOS_PRIMITIVE_USED:-spill_pressure}",
  "target_selector": "${CHAOS_TARGET_SELECTOR_USED:-ap_query_class:sort-heavy}",
  "ap_query_class": "${CHAOS_SPILL_QUERY_CLASS_USED:-${AP_CLASS:-sort-heavy}}",
  "ap_query_file": "${CHAOS_SPILL_QUERY_FILE_USED:-}",
  "session_memory": "${CHAOS_SESSION_MEMORY_USED:-}",
  "workers": "${CHAOS_WORKERS_USED:-0}",
  "status": "resolved"
}
EOF
      ;;
    *)
      cat > "$RUN_DIR/derived/target-selector.resolved.json" <<EOF
{
  "primitive": "${CHAOS_PRIMITIVE_USED:-none}",
  "target_selector": "${CHAOS_TARGET_SELECTOR_USED:-tp-hotspot/movie_freshness}",
  "target_movie_id": "${CHAOS_TARGET_MOVIE_ID:-}",
  "hot_modulus": "${JOB_TP_HOT_MODULUS:?missing JOB_TP_HOT_MODULUS}",
  "hot_remainder": "${JOB_TP_HOT_REMAINDER:?missing JOB_TP_HOT_REMAINDER}",
  "status": "resolved"
}
EOF
      ;;
  esac
}

write_waitxact_artifacts() {
  cat > "$RUN_DIR/derived/waitxact-chaos.json" <<EOF
{
  "rq": "${RQ:-P3CHAOS}",
  "dataset": "${DATASET:-job}",
  "variant": "${VARIANT:-go-mixed-waitxact-l1}",
  "primitive": "${CHAOS_PRIMITIVE_USED:-wait_xact}",
  "stage": "${CHAOS_STAGE_USED:-mixed-steady-state}",
  "intensity": "${CHAOS_INTENSITY_USED:-L1}",
  "target_selector": "${CHAOS_TARGET_SELECTOR_USED:-tp-hotspot/movie_freshness}",
  "target_movie_id": "${CHAOS_TARGET_MOVIE_ID:-}",
  "waiter_jobs": "${CHAOS_WAIT_JOBS_USED:-0}",
  "lock_hold_seconds": "${CHAOS_LOCK_HOLD_SECONDS_USED:-0}",
  "start_after_seconds": "${CHAOS_START_AFTER_SECONDS_USED:-0}",
  "duration_seconds": "${CHAOS_DURATION_SECONDS_USED:-0}",
  "fixture": "${CHAOS_FIXTURE_USED:-false}",
  "wait_duration_ms": "${CHAOS_WAIT_DURATION_MS:-0}",
  "waiter_failure_count": "${CHAOS_WAITER_FAILURE_COUNT:-0}",
  "waiter_count": "${CHAOS_TOTAL_WAITER_COUNT:-0}",
  "blocker_exit_code": "${CHAOS_BLOCKER_EXIT_CODE:-0}",
  "status": "${CHAOS_STATUS_USED:-unknown}"
}
EOF

  cat > "$RUN_DIR/derived/cleanup-report.json" <<EOF
{
  "primitive": "${CHAOS_PRIMITIVE_USED:-wait_xact}",
  "cleanup_profile": "${CHAOS_CLEANUP_PROFILE:-pg-default}",
  "manual_intervention_count": 0,
  "blocker_exit_code": "${CHAOS_BLOCKER_EXIT_CODE:-0}",
  "waiter_failure_count": "${CHAOS_WAITER_FAILURE_COUNT:-0}",
  "post_chaos_unstable_window_ms": "$(cleanup_unstable_window_ms)",
  "status": "${CHAOS_STATUS_USED:-unknown}"
}
EOF
}

write_deadlock_artifacts() {
  cat > "$RUN_DIR/derived/deadlock-pair-chaos.json" <<EOF
{
  "rq": "${RQ:-P3CHAOS}",
  "dataset": "${DATASET:-job}",
  "variant": "${VARIANT:-go-mixed-deadlock-l1}",
  "primitive": "${CHAOS_PRIMITIVE_USED:-deadlock_pair}",
  "stage": "${CHAOS_STAGE_USED:-mixed-steady-state}",
  "intensity": "${CHAOS_INTENSITY_USED:-L1}",
  "target_selector": "${CHAOS_TARGET_SELECTOR_USED:-fixture_rows:2}",
  "deadlock_jobs": "${CHAOS_DEADLOCK_JOBS_USED:-0}",
  "row_a_movie_id": "${CHAOS_DEADLOCK_ROW_1_ID:-}",
  "row_b_movie_id": "${CHAOS_DEADLOCK_ROW_2_ID:-}",
  "start_after_seconds": "${CHAOS_START_AFTER_SECONDS_USED:-0}",
  "duration_seconds": "${CHAOS_DURATION_SECONDS_USED:-0}",
  "elapsed_ms": "${CHAOS_DEADLOCK_ELAPSED_MS:-0}",
  "deadlock_detected_count": "${CHAOS_DEADLOCK_DETECTED_COUNT:-0}",
  "committed_session_count": "${CHAOS_DEADLOCK_COMMIT_COUNT:-0}",
  "aborted_session_count": "${CHAOS_DEADLOCK_ABORT_COUNT:-0}",
  "session_failure_count": "${CHAOS_DEADLOCK_SESSION_FAILURE_COUNT:-0}",
  "status": "${CHAOS_STATUS_USED:-unknown}"
}
EOF

  cat > "$RUN_DIR/derived/cleanup-report.json" <<EOF
{
  "primitive": "${CHAOS_PRIMITIVE_USED:-deadlock_pair}",
  "cleanup_profile": "${CHAOS_CLEANUP_PROFILE:-pg-default}",
  "manual_intervention_count": 0,
  "deadlock_detected_count": "${CHAOS_DEADLOCK_DETECTED_COUNT:-0}",
  "committed_session_count": "${CHAOS_DEADLOCK_COMMIT_COUNT:-0}",
  "aborted_session_count": "${CHAOS_DEADLOCK_ABORT_COUNT:-0}",
  "post_chaos_unstable_window_ms": "$(cleanup_unstable_window_ms)",
  "status": "${CHAOS_STATUS_USED:-unknown}"
}
EOF
}

capture_temp_spill_metrics() {
  local output_file="$1"
  bash "$EXP_ROOT/adapters/pg-like/temp_spill_metrics.sh" \
    --database "${BENCHMARK_DB_NAME:-${JOB_DB_NAME:?missing JOB_DB_NAME}}" \
    --output "$output_file"
}

read_temp_spill_metric() {
  local metrics_file="$1"
  local metric_name="$2"
  "${PYTHON_BIN:-python}" - "$metrics_file" "$metric_name" "${BENCHMARK_DB_NAME:-${JOB_DB_NAME:?missing JOB_DB_NAME}}" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
metric = sys.argv[2]
database = sys.argv[3]
column_index = {"temp_files": 1, "temp_bytes": 2}[metric]
if not path.exists():
    print("0")
    raise SystemExit(0)
for line in path.read_text(encoding="utf-8").splitlines():
    parts = line.split("|")
    if len(parts) >= 3 and parts[0] == database:
        print(parts[column_index])
        raise SystemExit(0)
print("0")
PY
}

resolve_spill_query_class() {
  local selector="${CHAOS_TARGET_SELECTOR:-}"
  if [[ "$selector" == ap_query_class:* ]]; then
    printf '%s\n' "${selector#ap_query_class:}"
    return
  fi
  printf '%s\n' "${AP_CLASS:-sort-heavy}"
}

cleanup_unstable_window_ms() {
  job_cleanup_unstable_window_ms
}

write_spill_artifacts() {
  cat > "$RUN_DIR/derived/spill-pressure-chaos.json" <<EOF
{
  "rq": "${RQ:-P3CHAOS}",
  "dataset": "${DATASET:-job}",
  "variant": "${VARIANT:-go-mixed-spill-l1}",
  "primitive": "${CHAOS_PRIMITIVE_USED:-spill_pressure}",
  "stage": "${CHAOS_STAGE_USED:-mixed-steady-state}",
  "intensity": "${CHAOS_INTENSITY_USED:-L1}",
  "target_selector": "${CHAOS_TARGET_SELECTOR_USED:-ap_query_class:sort-heavy}",
  "ap_query_class": "${CHAOS_SPILL_QUERY_CLASS_USED:-sort-heavy}",
  "ap_query_file": "${CHAOS_SPILL_QUERY_FILE_USED:-}",
  "workers": "${CHAOS_WORKERS_USED:-0}",
  "session_memory": "${CHAOS_SESSION_MEMORY_USED:-}",
  "requested_rate_qps": "${CHAOS_RATE_USED:-0}",
  "start_after_seconds": "${CHAOS_START_AFTER_SECONDS_USED:-0}",
  "duration_seconds": "${CHAOS_DURATION_SECONDS_USED:-0}",
  "elapsed_ms": "${CHAOS_SPILL_ELAPSED_MS:-0}",
  "temp_files_before": "${CHAOS_SPILL_TEMP_FILES_BEFORE:-0}",
  "temp_files_after": "${CHAOS_SPILL_TEMP_FILES_AFTER:-0}",
  "temp_files_delta": "${CHAOS_SPILL_TEMP_FILES_DELTA:-0}",
  "temp_bytes_before": "${CHAOS_SPILL_TEMP_BYTES_BEFORE:-0}",
  "temp_bytes_after": "${CHAOS_SPILL_TEMP_BYTES_AFTER:-0}",
  "temp_bytes_delta": "${CHAOS_SPILL_TEMP_BYTES_DELTA:-0}",
  "spill_severity_bytes": "${CHAOS_SPILL_TEMP_BYTES_DELTA:-0}",
  "worker_failure_count": "${CHAOS_SPILL_WORKER_FAILURE_COUNT:-0}",
  "total_rounds": "${CHAOS_SPILL_TOTAL_ROUNDS:-0}",
  "actual_rate_qps": "${CHAOS_SPILL_EXECUTION_RATE_QPS:-0}",
  "status": "${CHAOS_STATUS_USED:-unknown}"
}
EOF

  cat > "$RUN_DIR/derived/cleanup-report.json" <<EOF
{
  "primitive": "${CHAOS_PRIMITIVE_USED:-spill_pressure}",
  "cleanup_profile": "${CHAOS_CLEANUP_PROFILE:-pg-default}",
  "manual_intervention_count": 0,
  "worker_failure_count": "${CHAOS_SPILL_WORKER_FAILURE_COUNT:-0}",
  "temp_files_delta": "${CHAOS_SPILL_TEMP_FILES_DELTA:-0}",
  "temp_bytes_delta": "${CHAOS_SPILL_TEMP_BYTES_DELTA:-0}",
  "post_chaos_unstable_window_ms": "$(cleanup_unstable_window_ms)",
  "status": "${CHAOS_STATUS_USED:-unknown}"
}
EOF
}

run_spill_worker() {
  local worker_id="$1"
  local deadline_epoch="$2"
  local session_memory="$3"
  local rate_qps="$4"
  local database="${BENCHMARK_DB_NAME:-${JOB_DB_NAME:?missing JOB_DB_NAME}}"
  local pg_user="${AP_USER:-${BENCH_USER:-${DB_SUPERUSER:-postgres}}}"
  local pg_password="${AP_PASSWORD:-${BENCH_PASSWORD:-${DB_SUPERUSER_PASSWORD:-postgres}}}"
  local worker_dir="$RUN_DIR/chaos/spill/worker-$(printf '%02d' "$worker_id")"
  local sql_body query_body round round_log sleep_interval
  mkdir -p "$worker_dir"
  query_body="$(cat "$CHAOS_SPILL_QUERY_FILE_USED")"
  round=0
  sleep_interval="$("${PYTHON_BIN:-python}" - "$rate_qps" <<'PY'
import sys
rate = float(sys.argv[1])
print(f"{0 if rate <= 0 else 1.0 / rate:.6f}")
PY
)"

  while [[ $(date +%s) -lt $deadline_epoch ]]; do
    round=$((round + 1))
    round_log="$worker_dir/round-$(printf '%03d' "$round").log"
    sql_body=$(cat <<EOF
SET work_mem = '${session_memory}';
${query_body}
EOF
)
    if is_source_runtime; then
      printf '%s\n' "$sql_body" | \
        PGPASSWORD="$pg_password" \
        PGAPPNAME="paper1-chaos/spill_pressure/worker-${worker_id}" \
        "$(source_pg_bin_dir)/psql" \
        -h "$(source_pg_host)" \
        -p "$(source_pg_port)" \
        -U "$pg_user" \
        -d "$database" \
        -v ON_ERROR_STOP=1 > "$round_log" 2>&1
    else
      printf '%s\n' "$sql_body" | \
        compose exec -T \
          -e PGAPPNAME="paper1-chaos/spill_pressure/worker-${worker_id}" \
          -e PGPASSWORD="$pg_password" \
          "${DB_SERVICE_NAME:-postgres}" \
          psql -h 127.0.0.1 -U "$pg_user" -d "$database" -v ON_ERROR_STOP=1 > "$round_log" 2>&1
    fi

    if [[ "$sleep_interval" != "0.000000" && "$sleep_interval" != "0" ]] && [[ $(date +%s) -lt $deadline_epoch ]]; then
      sleep "$sleep_interval"
    fi
  done

  printf '%s\n' "$round" > "$worker_dir/rounds.txt"
}

run_wait_xact_injection() {
  local deadline_epoch="$1"
  local start_after="${CHAOS_START_AFTER_SECONDS:-0}"
  local lock_hold_seconds="${CHAOS_LOCK_HOLD_SECONDS:-${JOB_CHAOS_WAIT_LOCK_HOLD_SECONDS:?missing JOB_CHAOS_WAIT_LOCK_HOLD_SECONDS}}"
  local waiter_jobs="${CHAOS_JOBS:-${JOB_CHAOS_WAIT_JOBS:?missing JOB_CHAOS_WAIT_JOBS}}"
  local fixture="${CHAOS_FIXTURE:-false}"
  local blocker_sql waiter_sql blocker_pid waiter_started_ms last_waiter_finished_ms waiter_status
  local -a waiter_pids=()

  CHAOS_PRIMITIVE_USED="wait_xact"
  CHAOS_STAGE_USED="${CHAOS_STAGE:-mixed-steady-state}"
  CHAOS_TARGET_SELECTOR_USED="${CHAOS_TARGET_SELECTOR:-tp-hotspot/movie_freshness}"
  CHAOS_INTENSITY_USED="${CHAOS_INTENSITY:-L1}"
  CHAOS_START_AFTER_SECONDS_USED="$start_after"
  CHAOS_LOCK_HOLD_SECONDS_USED="$lock_hold_seconds"
  CHAOS_DURATION_SECONDS_USED="${CHAOS_DURATION_SECONDS:-$lock_hold_seconds}"
  CHAOS_WAIT_JOBS_USED="$waiter_jobs"
  CHAOS_FIXTURE_USED="$fixture"
  CHAOS_TOTAL_WAITER_COUNT="$waiter_jobs"

  if [[ "$fixture" != "true" ]]; then
    fail "wait_xact currently requires CHAOS_FIXTURE=true"
  fi

  if (( $(date +%s) + start_after >= deadline_epoch )); then
    CHAOS_STATUS_USED="skipped-after-deadline"
    append_chaos_event "chaos-skipped" "after-deadline"
    write_waitxact_artifacts
    return 0
  fi

  if (( start_after > 0 )); then
    append_chaos_event "chaos-scheduled" "sleep-${start_after}s"
    sleep "$start_after"
  fi
  if [[ $(date +%s) -ge $deadline_epoch ]]; then
    CHAOS_STATUS_USED="skipped-after-deadline"
    append_chaos_event "chaos-skipped" "deadline-passed"
    write_waitxact_artifacts
    return 0
  fi

  CHAOS_TARGET_MOVIE_ID="$(resolve_lock_target_movie_id)"
  [[ -n "$CHAOS_TARGET_MOVIE_ID" ]] || fail "failed to resolve lock target movie_id for wait_xact"
  write_target_selector_resolved

  blocker_sql=$(cat <<EOF
BEGIN;
SELECT movie_id FROM movie_freshness WHERE movie_id = $CHAOS_TARGET_MOVIE_ID FOR UPDATE;
SELECT pg_sleep($lock_hold_seconds);
COMMIT;
EOF
)
  waiter_sql=$(cat <<EOF
UPDATE movie_freshness
SET epoch = epoch + 1,
    hot_flag = true,
    freshness_score = freshness_score + 1,
    last_touch_ts = now()
WHERE movie_id = $CHAOS_TARGET_MOVIE_ID;
EOF
)

  append_chaos_event "chaos-started" "wait_xact-blocker"
  start_psql_session "paper1-chaos/wait_xact/blocker" "$RUN_DIR/lock/blocker.log" "$blocker_sql"
  blocker_pid="$START_PSQL_SESSION_PID"
  CHAOS_PIDS+=("$blocker_pid")
  sleep 2

  waiter_started_ms="$(date +%s%3N)"
  for ((worker_id = 1; worker_id <= waiter_jobs; worker_id++)); do
    start_psql_session "paper1-chaos/wait_xact/waiter-${worker_id}" "$RUN_DIR/lock/waiter-$(printf '%02d' "$worker_id").log" "$waiter_sql"
    waiter_pids+=("$START_PSQL_SESSION_PID")
    CHAOS_PIDS+=("$START_PSQL_SESSION_PID")
  done

  sleep 2
  if [[ "${LOCK_OBSERVE_MODE:-snapshot}" != "off" ]]; then
    append_chaos_event "chaos-observed" "lock-snapshot"
    "${HARNESS_OBSERVE_LOCKS:-$PROJECT_ROOT/scripts/harness_observe_locks.sh}" --run-dir "$RUN_DIR" --database "${BENCHMARK_DB_NAME:-${JOB_DB_NAME:?missing JOB_DB_NAME}}" || true
    if [[ -f "$RUN_DIR/observability/lock-snapshot.csv" ]]; then
      cp "$RUN_DIR/observability/lock-snapshot.csv" "$RUN_DIR/observability/lock-snapshot.waitxact.csv"
    fi
    if [[ -f "$RUN_DIR/observability/blocking-tree.txt" ]]; then
      cp "$RUN_DIR/observability/blocking-tree.txt" "$RUN_DIR/observability/blocking-tree.waitxact.txt"
    fi
  fi

  CHAOS_WAITER_FAILURE_COUNT="0"
  last_waiter_finished_ms="$waiter_started_ms"
  set +e
  for pid in "${waiter_pids[@]}"; do
    wait "$pid"
    waiter_status=$?
    if (( waiter_status != 0 )); then
      CHAOS_WAITER_FAILURE_COUNT="$(( CHAOS_WAITER_FAILURE_COUNT + 1 ))"
    fi
    last_waiter_finished_ms="$(date +%s%3N)"
  done
  wait "$blocker_pid"
  CHAOS_BLOCKER_EXIT_CODE="$?"
  set -e

  CHAOS_WAIT_DURATION_MS="$(( last_waiter_finished_ms - waiter_started_ms ))"
  if [[ "$CHAOS_BLOCKER_EXIT_CODE" == "0" && "$CHAOS_WAITER_FAILURE_COUNT" == "0" ]]; then
    CHAOS_STATUS_USED="completed"
    append_chaos_event "chaos-finished" "waitxact-completed"
  else
    CHAOS_STATUS_USED="failed"
    append_chaos_event "chaos-finished" "waitxact-failed"
  fi
  write_waitxact_artifacts

  if [[ "$CHAOS_STATUS_USED" != "completed" ]]; then
    return 1
  fi
}

run_deadlock_pair_injection() {
  local deadline_epoch="$1"
  local start_after="${CHAOS_START_AFTER_SECONDS:-0}"
  local duration_seconds="${CHAOS_DURATION_SECONDS:-${JOB_CHAOS_DEADLOCK_DURATION_SECONDS:?missing JOB_CHAOS_DEADLOCK_DURATION_SECONDS}}"
  local deadlock_timeout_ms="${JOB_CHAOS_DEADLOCK_TIMEOUT_MS:?missing JOB_CHAOS_DEADLOCK_TIMEOUT_MS}"
  local session_a_sql session_b_sql session_a_pid session_b_pid session_a_status session_b_status
  local deadlock_started_ms deadlock_finished_ms
  local -a deadlock_rows=()

  CHAOS_PRIMITIVE_USED="deadlock_pair"
  CHAOS_STAGE_USED="${CHAOS_STAGE:-mixed-steady-state}"
  CHAOS_TARGET_SELECTOR_USED="${CHAOS_TARGET_SELECTOR:-fixture_rows:2}"
  CHAOS_INTENSITY_USED="${CHAOS_INTENSITY:-L1}"
  CHAOS_START_AFTER_SECONDS_USED="$start_after"
  CHAOS_DURATION_SECONDS_USED="$duration_seconds"
  CHAOS_DEADLOCK_JOBS_USED="${CHAOS_JOBS:-${JOB_CHAOS_DEADLOCK_JOBS:?missing JOB_CHAOS_DEADLOCK_JOBS}}"

  if [[ "$CHAOS_DEADLOCK_JOBS_USED" != "1" ]]; then
    fail "deadlock_pair currently supports exactly one job"
  fi

  if (( $(date +%s) + start_after >= deadline_epoch )); then
    CHAOS_STATUS_USED="skipped-after-deadline"
    append_chaos_event "chaos-skipped" "deadlock-after-deadline"
    write_target_selector_resolved
    write_deadlock_artifacts
    return 0
  fi

  if (( start_after > 0 )); then
    append_chaos_event "chaos-scheduled" "deadlock-sleep-${start_after}s"
    sleep "$start_after"
  fi
  if [[ $(date +%s) -ge $deadline_epoch ]]; then
    CHAOS_STATUS_USED="skipped-after-deadline"
    append_chaos_event "chaos-skipped" "deadlock-deadline-passed"
    write_target_selector_resolved
    write_deadlock_artifacts
    return 0
  fi

  mapfile -t deadlock_rows < <(resolve_deadlock_target_movie_ids)
  if (( ${#deadlock_rows[@]} != 2 )); then
    fail "deadlock_pair requires exactly two resolved fixture rows"
  fi
  CHAOS_DEADLOCK_ROW_1_ID="${deadlock_rows[0]}"
  CHAOS_DEADLOCK_ROW_2_ID="${deadlock_rows[1]}"
  write_target_selector_resolved

  session_a_sql=$(cat <<EOF
\set VERBOSITY verbose
SET deadlock_timeout = '${deadlock_timeout_ms}ms';
BEGIN;
UPDATE movie_freshness
SET epoch = epoch + 1,
    hot_flag = true,
    freshness_score = freshness_score + 1,
    last_touch_ts = now()
WHERE movie_id = ${CHAOS_DEADLOCK_ROW_1_ID};
SELECT pg_sleep(1);
UPDATE movie_freshness
SET epoch = epoch + 1,
    hot_flag = true,
    freshness_score = freshness_score + 1,
    last_touch_ts = now()
WHERE movie_id = ${CHAOS_DEADLOCK_ROW_2_ID};
COMMIT;
EOF
)
  session_b_sql=$(cat <<EOF
\set VERBOSITY verbose
SET deadlock_timeout = '${deadlock_timeout_ms}ms';
BEGIN;
UPDATE movie_freshness
SET epoch = epoch + 1,
    hot_flag = true,
    freshness_score = freshness_score + 1,
    last_touch_ts = now()
WHERE movie_id = ${CHAOS_DEADLOCK_ROW_2_ID};
SELECT pg_sleep(1);
UPDATE movie_freshness
SET epoch = epoch + 1,
    hot_flag = true,
    freshness_score = freshness_score + 1,
    last_touch_ts = now()
WHERE movie_id = ${CHAOS_DEADLOCK_ROW_1_ID};
COMMIT;
EOF
)

  append_chaos_event "chaos-started" "deadlock-pair"
  deadlock_started_ms="$(date +%s%3N)"
  start_psql_session "paper1-chaos/deadlock_pair/session-a" "$RUN_DIR/lock/deadlock-session-a.log" "$session_a_sql"
  session_a_pid="$START_PSQL_SESSION_PID"
  CHAOS_PIDS+=("$session_a_pid")
  start_psql_session "paper1-chaos/deadlock_pair/session-b" "$RUN_DIR/lock/deadlock-session-b.log" "$session_b_sql"
  session_b_pid="$START_PSQL_SESSION_PID"
  CHAOS_PIDS+=("$session_b_pid")

  sleep 2
  if [[ "${LOCK_OBSERVE_MODE:-snapshot}" != "off" ]]; then
    append_chaos_event "chaos-observed" "deadlock-lock-snapshot"
    "${HARNESS_OBSERVE_LOCKS:-$PROJECT_ROOT/scripts/harness_observe_locks.sh}" --run-dir "$RUN_DIR" --database "${BENCHMARK_DB_NAME:-${JOB_DB_NAME:?missing JOB_DB_NAME}}" || true
    if [[ -f "$RUN_DIR/observability/lock-snapshot.csv" ]]; then
      cp "$RUN_DIR/observability/lock-snapshot.csv" "$RUN_DIR/observability/lock-snapshot.deadlock.csv"
    fi
    if [[ -f "$RUN_DIR/observability/blocking-tree.txt" ]]; then
      cp "$RUN_DIR/observability/blocking-tree.txt" "$RUN_DIR/observability/blocking-tree.deadlock.txt"
    fi
  fi

  set +e
  wait "$session_a_pid"
  session_a_status=$?
  wait "$session_b_pid"
  session_b_status=$?
  set -e
  deadlock_finished_ms="$(date +%s%3N)"
  CHAOS_DEADLOCK_ELAPSED_MS="$(( deadlock_finished_ms - deadlock_started_ms ))"

  CHAOS_DEADLOCK_COMMIT_COUNT="0"
  CHAOS_DEADLOCK_ABORT_COUNT="0"
  if (( session_a_status == 0 )); then
    CHAOS_DEADLOCK_COMMIT_COUNT="$(( CHAOS_DEADLOCK_COMMIT_COUNT + 1 ))"
  else
    CHAOS_DEADLOCK_ABORT_COUNT="$(( CHAOS_DEADLOCK_ABORT_COUNT + 1 ))"
  fi
  if (( session_b_status == 0 )); then
    CHAOS_DEADLOCK_COMMIT_COUNT="$(( CHAOS_DEADLOCK_COMMIT_COUNT + 1 ))"
  else
    CHAOS_DEADLOCK_ABORT_COUNT="$(( CHAOS_DEADLOCK_ABORT_COUNT + 1 ))"
  fi
  CHAOS_DEADLOCK_SESSION_FAILURE_COUNT="$CHAOS_DEADLOCK_ABORT_COUNT"
  CHAOS_DEADLOCK_DETECTED_COUNT="0"
  if [[ -f "$RUN_DIR/lock/deadlock-session-a.log" ]] && grep -qi "deadlock detected" "$RUN_DIR/lock/deadlock-session-a.log"; then
    CHAOS_DEADLOCK_DETECTED_COUNT="$(( CHAOS_DEADLOCK_DETECTED_COUNT + 1 ))"
  fi
  if [[ -f "$RUN_DIR/lock/deadlock-session-b.log" ]] && grep -qi "deadlock detected" "$RUN_DIR/lock/deadlock-session-b.log"; then
    CHAOS_DEADLOCK_DETECTED_COUNT="$(( CHAOS_DEADLOCK_DETECTED_COUNT + 1 ))"
  fi

  if [[ "$CHAOS_DEADLOCK_DETECTED_COUNT" -ge 1 && "$CHAOS_DEADLOCK_COMMIT_COUNT" -ge 1 && "$CHAOS_DEADLOCK_ABORT_COUNT" -ge 1 ]]; then
    CHAOS_STATUS_USED="completed"
    append_chaos_event "chaos-finished" "deadlock-completed"
  else
    CHAOS_STATUS_USED="failed"
    append_chaos_event "chaos-finished" "deadlock-failed"
  fi
  write_deadlock_artifacts

  if [[ "$CHAOS_STATUS_USED" != "completed" ]]; then
    return 1
  fi
}

run_spill_pressure_injection() {
  local deadline_epoch="$1"
  local start_after="${CHAOS_START_AFTER_SECONDS:-0}"
  local duration_seconds="${CHAOS_DURATION_SECONDS:-${JOB_CHAOS_SPILL_DURATION_SECONDS:?missing JOB_CHAOS_SPILL_DURATION_SECONDS}}"
  local workers="${CHAOS_WORKERS:-${JOB_CHAOS_SPILL_WORKERS:?missing JOB_CHAOS_SPILL_WORKERS}}"
  local session_memory="${CHAOS_SESSION_MEMORY:-${JOB_CHAOS_SPILL_SESSION_MEMORY:?missing JOB_CHAOS_SPILL_SESSION_MEMORY}}"
  local rate_qps="${CHAOS_RATE:-${JOB_CHAOS_SPILL_RATE_QPS:?missing JOB_CHAOS_SPILL_RATE_QPS}}"
  local spill_query_class spill_deadline_epoch spill_started_ms spill_finished_ms worker_status total_rounds file rounds
  local -a spill_pids=()

  CHAOS_PRIMITIVE_USED="spill_pressure"
  CHAOS_STAGE_USED="${CHAOS_STAGE:-mixed-steady-state}"
  CHAOS_TARGET_SELECTOR_USED="${CHAOS_TARGET_SELECTOR:-ap_query_class:${AP_CLASS:-sort-heavy}}"
  CHAOS_INTENSITY_USED="${CHAOS_INTENSITY:-L1}"
  CHAOS_START_AFTER_SECONDS_USED="$start_after"
  CHAOS_DURATION_SECONDS_USED="$duration_seconds"
  CHAOS_WORKERS_USED="$workers"
  CHAOS_SESSION_MEMORY_USED="$session_memory"
  CHAOS_RATE_USED="$rate_qps"
  CHAOS_SPILL_QUERY_CLASS_USED="$(resolve_spill_query_class)"
  CHAOS_SPILL_QUERY_FILE_USED="$(resolve_ap_query_for_class "$CHAOS_SPILL_QUERY_CLASS_USED")"

  if (( $(date +%s) + start_after >= deadline_epoch )); then
    CHAOS_STATUS_USED="skipped-after-deadline"
    append_chaos_event "chaos-skipped" "spill-pressure-after-deadline"
    write_target_selector_resolved
    write_spill_artifacts
    return 0
  fi

  if (( start_after > 0 )); then
    append_chaos_event "chaos-scheduled" "spill-pressure-sleep-${start_after}s"
    sleep "$start_after"
  fi
  if [[ $(date +%s) -ge $deadline_epoch ]]; then
    CHAOS_STATUS_USED="skipped-after-deadline"
    append_chaos_event "chaos-skipped" "spill-pressure-deadline-passed"
    write_target_selector_resolved
    write_spill_artifacts
    return 0
  fi

  write_target_selector_resolved
  capture_temp_spill_metrics "$RUN_DIR/observability/temp-spill.before.csv"
  CHAOS_SPILL_TEMP_FILES_BEFORE="$(read_temp_spill_metric "$RUN_DIR/observability/temp-spill.before.csv" temp_files)"
  CHAOS_SPILL_TEMP_BYTES_BEFORE="$(read_temp_spill_metric "$RUN_DIR/observability/temp-spill.before.csv" temp_bytes)"

  spill_started_ms="$(date +%s%3N)"
  spill_deadline_epoch=$(( $(date +%s) + duration_seconds ))
  if (( spill_deadline_epoch > deadline_epoch )); then
    spill_deadline_epoch="$deadline_epoch"
  fi
  append_chaos_event "chaos-started" "spill-pressure"
  for ((worker_id = 1; worker_id <= workers; worker_id++)); do
    run_spill_worker "$worker_id" "$spill_deadline_epoch" "$session_memory" "$rate_qps" &
    spill_pids+=("$!")
    CHAOS_PIDS+=("$!")
  done

  CHAOS_SPILL_WORKER_FAILURE_COUNT="0"
  set +e
  for pid in "${spill_pids[@]}"; do
    wait "$pid"
    worker_status=$?
    if (( worker_status != 0 )); then
      CHAOS_SPILL_WORKER_FAILURE_COUNT="$(( CHAOS_SPILL_WORKER_FAILURE_COUNT + 1 ))"
    fi
  done
  set -e
  spill_finished_ms="$(date +%s%3N)"
  CHAOS_SPILL_ELAPSED_MS="$(( spill_finished_ms - spill_started_ms ))"

  total_rounds=0
  shopt -s nullglob
  for file in "$RUN_DIR"/chaos/spill/worker-*/rounds.txt; do
    rounds="$(tr -d '\r\n' < "$file")"
    total_rounds=$((total_rounds + rounds))
  done
  shopt -u nullglob
  CHAOS_SPILL_TOTAL_ROUNDS="$total_rounds"

  capture_temp_spill_metrics "$RUN_DIR/observability/temp-spill.after.csv"
  CHAOS_SPILL_TEMP_FILES_AFTER="$(read_temp_spill_metric "$RUN_DIR/observability/temp-spill.after.csv" temp_files)"
  CHAOS_SPILL_TEMP_BYTES_AFTER="$(read_temp_spill_metric "$RUN_DIR/observability/temp-spill.after.csv" temp_bytes)"
  CHAOS_SPILL_TEMP_FILES_DELTA="$(( CHAOS_SPILL_TEMP_FILES_AFTER - CHAOS_SPILL_TEMP_FILES_BEFORE ))"
  CHAOS_SPILL_TEMP_BYTES_DELTA="$(( CHAOS_SPILL_TEMP_BYTES_AFTER - CHAOS_SPILL_TEMP_BYTES_BEFORE ))"
  CHAOS_SPILL_EXECUTION_RATE_QPS="$("${PYTHON_BIN:-python}" - "$CHAOS_SPILL_TOTAL_ROUNDS" "$CHAOS_SPILL_ELAPSED_MS" <<'PY'
import sys
rounds = int(sys.argv[1])
elapsed_ms = int(sys.argv[2])
if elapsed_ms <= 0:
    print("0")
else:
    print(f"{rounds / (elapsed_ms / 1000.0):.4f}")
PY
)"

  if [[ "$CHAOS_SPILL_WORKER_FAILURE_COUNT" == "0" && "$CHAOS_SPILL_TEMP_BYTES_DELTA" -gt 0 ]]; then
    CHAOS_STATUS_USED="completed"
    append_chaos_event "chaos-finished" "spill-pressure-completed"
  elif [[ "$CHAOS_SPILL_WORKER_FAILURE_COUNT" == "0" ]]; then
    CHAOS_STATUS_USED="no-spill-observed"
    append_chaos_event "chaos-finished" "spill-pressure-no-spill"
  else
    CHAOS_STATUS_USED="failed"
    append_chaos_event "chaos-finished" "spill-pressure-failed"
  fi
  write_spill_artifacts

  if [[ "$CHAOS_STATUS_USED" != "completed" ]]; then
    return 1
  fi
}

run_multi_fault_injection() {
  local deadline_epoch="$1"
  local status=0
  local original_mode="${CHAOS_MODE:-none}"
  local original_primitive="${CHAOS_PRIMITIVE:-}"
  local original_stage="${CHAOS_STAGE:-}"
  local original_target_selector="${CHAOS_TARGET_SELECTOR:-}"
  local original_intensity="${CHAOS_INTENSITY:-}"
  local original_start_after="${CHAOS_START_AFTER_SECONDS:-0}"
  local original_duration="${CHAOS_DURATION_SECONDS:-0}"
  local original_jobs="${CHAOS_JOBS:-}"
  local original_lock_hold="${CHAOS_LOCK_HOLD_SECONDS:-}"
  local original_fixture="${CHAOS_FIXTURE:-}"
  local original_workers="${CHAOS_WORKERS:-}"
  local original_session_memory="${CHAOS_SESSION_MEMORY:-}"
  local original_rate="${CHAOS_RATE:-}"
  local original_spill_query_class="${CHAOS_SPILL_QUERY_CLASS:-}"
  local injection_ids raw_ids
  local injection_count=0
  local idx primitive stage target_selector intensity start_after duration jobs lock_hold fixture workers session_memory rate spill_query_class

  raw_ids="${CHAOS_INJECTION_IDS:-}"
  if [[ -z "$raw_ids" ]]; then
    fail "multi-fault chaos mode requires CHAOS_INJECTION_IDS"
  fi

  IFS='|' read -r -a injection_ids <<< "$raw_ids"
  for idx in "${!injection_ids[@]}"; do
    primitive_var="CHAOS_INJECTION_$((idx + 1))_PRIMITIVE"
    primitive="${!primitive_var:-}"
    [[ -n "$primitive" ]] || continue
    injection_count=$((injection_count + 1))
  done
  if (( injection_count == 0 )); then
    fail "multi-fault chaos mode requires at least one configured injection"
  fi

  append_chaos_event "chaos-started" "multi-fault-${injection_count}"
  for idx in "${!injection_ids[@]}"; do
    primitive_var="CHAOS_INJECTION_$((idx + 1))_PRIMITIVE"
    primitive="${!primitive_var:-}"
    [[ -n "$primitive" ]] || continue

    stage_var="CHAOS_INJECTION_$((idx + 1))_STAGE"
    target_selector_var="CHAOS_INJECTION_$((idx + 1))_TARGET_SELECTOR"
    intensity_var="CHAOS_INJECTION_$((idx + 1))_INTENSITY"
    start_after_var="CHAOS_INJECTION_$((idx + 1))_START_AFTER_SECONDS"
    duration_var="CHAOS_INJECTION_$((idx + 1))_DURATION_SECONDS"
    jobs_var="CHAOS_INJECTION_$((idx + 1))_JOBS"
    lock_hold_var="CHAOS_INJECTION_$((idx + 1))_LOCK_HOLD_SECONDS"
    fixture_var="CHAOS_INJECTION_$((idx + 1))_FIXTURE"
    workers_var="CHAOS_INJECTION_$((idx + 1))_WORKERS"
    session_memory_var="CHAOS_INJECTION_$((idx + 1))_SESSION_MEMORY"
    rate_var="CHAOS_INJECTION_$((idx + 1))_RATE"
    spill_query_class_var="CHAOS_INJECTION_$((idx + 1))_SPILL_QUERY_CLASS"

    stage="${!stage_var:-$original_stage}"
    target_selector="${!target_selector_var:-$original_target_selector}"
    intensity="${!intensity_var:-$original_intensity}"
    start_after="${!start_after_var:-$original_start_after}"
    duration="${!duration_var:-$original_duration}"
    jobs="${!jobs_var:-$original_jobs}"
    lock_hold="${!lock_hold_var:-$original_lock_hold}"
    fixture="${!fixture_var:-$original_fixture}"
    workers="${!workers_var:-$original_workers}"
    session_memory="${!session_memory_var:-$original_session_memory}"
    rate="${!rate_var:-$original_rate}"
    spill_query_class="${!spill_query_class_var:-$original_spill_query_class}"

    export CHAOS_MODE="single-fault"
    export CHAOS_PRIMITIVE="$primitive"
    export CHAOS_STAGE="$stage"
    export CHAOS_TARGET_SELECTOR="$target_selector"
    export CHAOS_INTENSITY="$intensity"
    export CHAOS_START_AFTER_SECONDS="$start_after"
    export CHAOS_DURATION_SECONDS="$duration"
    export CHAOS_JOBS="$jobs"
    export CHAOS_LOCK_HOLD_SECONDS="$lock_hold"
    export CHAOS_FIXTURE="$fixture"
    export CHAOS_WORKERS="$workers"
    export CHAOS_SESSION_MEMORY="$session_memory"
    export CHAOS_RATE="$rate"
    export CHAOS_SPILL_QUERY_CLASS="$spill_query_class"

    case "$primitive" in
      wait_xact)
        run_wait_xact_injection "$deadline_epoch" || status=1
        ;;
      deadlock_pair)
        run_deadlock_pair_injection "$deadline_epoch" || status=1
        ;;
      spill_pressure)
        run_spill_pressure_injection "$deadline_epoch" || status=1
        ;;
      *)
        fail "unsupported multi-fault chaos primitive: $primitive"
        ;;
    esac

    if (( status != 0 )); then
      break
    fi
  done

  export CHAOS_MODE="$original_mode"
  export CHAOS_PRIMITIVE="$original_primitive"
  export CHAOS_STAGE="$original_stage"
  export CHAOS_TARGET_SELECTOR="$original_target_selector"
  export CHAOS_INTENSITY="$original_intensity"
  export CHAOS_START_AFTER_SECONDS="$original_start_after"
  export CHAOS_DURATION_SECONDS="$original_duration"
  export CHAOS_JOBS="$original_jobs"
  export CHAOS_LOCK_HOLD_SECONDS="$original_lock_hold"
  export CHAOS_FIXTURE="$original_fixture"
  export CHAOS_WORKERS="$original_workers"
  export CHAOS_SESSION_MEMORY="$original_session_memory"
  export CHAOS_RATE="$original_rate"
  export CHAOS_SPILL_QUERY_CLASS="$original_spill_query_class"

  if (( status != 0 )); then
    CHAOS_STATUS_USED="failed"
    append_chaos_event "chaos-finished" "multi-fault-failed"
    return 1
  fi

  CHAOS_STATUS_USED="completed"
  append_chaos_event "chaos-finished" "multi-fault-completed"
}

run_chaos_during_overlap() {
  local deadline_epoch="$1"
  case "${CHAOS_MODE:-none}" in
    ""|none)
      CHAOS_STATUS_USED="not-requested"
      return 0
      ;;
    single-fault)
      case "${CHAOS_PRIMITIVE:-none}" in
        wait_xact)
          run_wait_xact_injection "$deadline_epoch"
          ;;
        deadlock_pair)
          run_deadlock_pair_injection "$deadline_epoch"
          ;;
        spill_pressure)
          run_spill_pressure_injection "$deadline_epoch"
          ;;
        *)
          fail "unsupported single-fault chaos primitive: ${CHAOS_PRIMITIVE:-none}"
          ;;
      esac
      ;;
    multi-fault)
      run_multi_fault_injection "$deadline_epoch"
      ;;
    *)
      fail "unsupported CHAOS_MODE in mixed baseline: ${CHAOS_MODE:-none}"
      ;;
  esac
}

run_tp_pgbench() {
  local runtime_seconds="$1"
  local database="${BENCHMARK_DB_NAME:-${JOB_DB_NAME:?missing JOB_DB_NAME}}"
  local report_interval="${JOB_TP_REPORT_INTERVAL:?missing JOB_TP_REPORT_INTERVAL}"
  local pg_user="${JOB_TP_USER:-${BENCH_USER:-${DB_SUPERUSER:-postgres}}}"
  local pg_password="${JOB_TP_PASSWORD:-${BENCH_PASSWORD:-${DB_SUPERUSER_PASSWORD:-postgres}}}"
  local -a rate_args=()

  if [[ "$TP_RATE_CAP_USED" =~ ^[0-9]+$ ]]; then
    if (( TP_RATE_CAP_USED > 0 )); then
      rate_args=(--rate "$TP_RATE_CAP_USED")
    fi
  elif [[ "$TP_RATE_CAP_USED" != "none" && -n "$TP_RATE_CAP_USED" ]]; then
    echo "invalid JOB_TP_RATE_CAP: $TP_RATE_CAP_USED" >&2
    exit 1
  fi

  ensure_env_file
  if is_source_runtime; then
    PGPASSWORD="$pg_password" PGAPPNAME="${PGAPPNAME:-paper1-jobtp-mixed}" "$(source_pg_bin_dir)/pgbench" \
      -h "$(source_pg_host)" \
      -p "$(source_pg_port)" \
      -U "$pg_user" \
      -d "$database" \
      --client "$TP_TERMINALS_USED" \
      --jobs "$TP_THREADS_USED" \
      --time "$runtime_seconds" \
      --progress "$report_interval" \
      "${rate_args[@]}" \
      --file "$(workspace_to_host_path "$TP_SQL_FILE_USED")" \
      --no-vacuum \
      --protocol prepared \
      --define "batch_size=${JOB_TP_BATCH_SIZE:?missing JOB_TP_BATCH_SIZE}" \
      --define "hot_modulus=${JOB_TP_HOT_MODULUS:?missing JOB_TP_HOT_MODULUS}" \
      --define "hot_remainder=${JOB_TP_HOT_REMAINDER:?missing JOB_TP_HOT_REMAINDER}" \
      2>&1 | tee "$TP_LOG_FILE_USED"
  else
    compose exec -T \
      -e PGAPPNAME="${PGAPPNAME:-paper1-jobtp-mixed}" \
      -e PGPASSWORD="$pg_password" \
      "${DB_SERVICE_NAME:-postgres}" \
      pgbench -h 127.0.0.1 -p 5432 -U "$pg_user" -d "$database" \
      --client "$TP_TERMINALS_USED" \
      --jobs "$TP_THREADS_USED" \
      --time "$runtime_seconds" \
      --progress "$report_interval" \
      "${rate_args[@]}" \
      --file "$TP_SQL_FILE_USED" \
      --no-vacuum \
      --protocol prepared \
      --define "batch_size=${JOB_TP_BATCH_SIZE:?missing JOB_TP_BATCH_SIZE}" \
      --define "hot_modulus=${JOB_TP_HOT_MODULUS:?missing JOB_TP_HOT_MODULUS}" \
      --define "hot_remainder=${JOB_TP_HOT_REMAINDER:?missing JOB_TP_HOT_REMAINDER}" \
      2>&1 | tee "$TP_LOG_FILE_USED"
  fi

  finalize_tp_artifacts
}

run_tp_sysbench() {
  local runtime_seconds="$1"
  local database="${BENCHMARK_DB_NAME:-${JOB_DB_NAME:?missing JOB_DB_NAME}}"
  local report_interval="${JOB_TP_REPORT_INTERVAL:?missing JOB_TP_REPORT_INTERVAL}"
  local pg_user="${JOB_TP_USER:-${BENCH_USER:-${DB_SUPERUSER:-postgres}}}"
  local pg_password="${JOB_TP_PASSWORD:-${BENCH_PASSWORD:-${DB_SUPERUSER_PASSWORD:-postgres}}}"
  local pg_host="$(benchmark_pg_host)"
  local pg_port="$(benchmark_pg_port)"
  local sysbench_path="$(sysbench_bin)"
  local -a rate_args=()

  if [[ "$TP_RATE_CAP_USED" =~ ^[0-9]+$ ]]; then
    if (( TP_RATE_CAP_USED > 0 )); then
      rate_args=(--rate "$TP_RATE_CAP_USED")
    fi
  elif [[ "$TP_RATE_CAP_USED" != "none" && -n "$TP_RATE_CAP_USED" ]]; then
    echo "invalid JOB_TP_RATE_CAP: $TP_RATE_CAP_USED" >&2
    exit 1
  fi

  printf 'elapsed_seconds,tps,latency_ms,source\n' > "$TP_PROGRESS_FILE_USED"
  PGPASSWORD="$pg_password" PGAPPNAME="${PGAPPNAME:-paper1-jobtp-mixed}" "$sysbench_path" \
    --db-driver=pgsql \
    --pgsql-host="$pg_host" \
    --pgsql-port="$pg_port" \
    --pgsql-user="$pg_user" \
    --pgsql-password="$pg_password" \
    --pgsql-db="$database" \
    --threads="$TP_TERMINALS_USED" \
    --time="$runtime_seconds" \
    --report-interval="$report_interval" \
    "${rate_args[@]}" \
    --sql-file="$(workspace_to_host_path "$TP_SQL_FILE_USED")" \
    --batch-size="${JOB_TP_BATCH_SIZE:?missing JOB_TP_BATCH_SIZE}" \
    --hot-modulus="${JOB_TP_HOT_MODULUS:?missing JOB_TP_HOT_MODULUS}" \
    --hot-remainder="${JOB_TP_HOT_REMAINDER:?missing JOB_TP_HOT_REMAINDER}" \
    --progress-file="$TP_PROGRESS_FILE_USED" \
    "$TP_SYSBENCH_SCRIPT_USED" run 2>&1 | tee "$TP_LOG_FILE_USED"

  finalize_tp_artifacts
}

run_tp_driver() {
  local runtime_seconds="$1"
  case "$TP_DRIVER_USED" in
    pgbench)
      run_tp_pgbench "$runtime_seconds"
      ;;
    sysbench)
      run_tp_sysbench "$runtime_seconds"
      ;;
  esac
}

run_ap_worker() {
  local worker_id="$1"
  local deadline_epoch="$2"
  local sleep_between_rounds="$3"
  local database="${BENCHMARK_DB_NAME:-${JOB_DB_NAME:?missing JOB_DB_NAME}}"
  local pg_user="${AP_USER:-${BENCH_USER:-${DB_SUPERUSER:-postgres}}}"
  local pg_password="${AP_PASSWORD:-${BENCH_PASSWORD:-${DB_SUPERUSER_PASSWORD:-postgres}}}"
  local worker_dir="$RUN_DIR/ap/worker-$(printf '%02d' "$worker_id")"
  local sql_body round round_log ap_parallelism round_started_ms round_finished_ms round_status duration_ms
  mkdir -p "$worker_dir"
  sql_body="$(cat "$AP_QUERY_FILE_USED")"
  ap_parallelism="${AP_PARALLELISM:-0}"
  if [[ "$ap_parallelism" =~ ^[0-9]+$ ]] && (( ap_parallelism > 0 )); then
    sql_body=$(cat <<EOF
SET max_parallel_workers_per_gather = ${ap_parallelism};
${sql_body}
EOF
)
  fi
  round=0

  while [[ $(date +%s) -lt $deadline_epoch ]]; do
    round=$((round + 1))
    round_log="$worker_dir/round-$(printf '%03d' "$round").log"
    round_started_ms="$(date +%s%3N)"
    append_ap_event "round-started" "$worker_id" "$round" "started" "0" "$round_log"
    set +e
    if is_source_runtime; then
      printf '%s\n' "$sql_body" | \
        PGPASSWORD="$pg_password" \
        PGAPPNAME="paper1-ap/${worker_id}" \
        "$(source_pg_bin_dir)/psql" \
        -h "$(source_pg_host)" \
        -p "$(source_pg_port)" \
        -U "$pg_user" \
        -d "$database" \
        -v ON_ERROR_STOP=1 > "$round_log" 2>&1
    else
      printf '%s\n' "$sql_body" | \
        compose exec -T \
          -e PGAPPNAME="paper1-ap/${worker_id}" \
          -e PGPASSWORD="$pg_password" \
          "${DB_SERVICE_NAME:-postgres}" \
          psql -h 127.0.0.1 -U "$pg_user" -d "$database" -v ON_ERROR_STOP=1 > "$round_log" 2>&1
    fi
    round_status=$?
    set -e
    round_finished_ms="$(date +%s%3N)"
    duration_ms="$(( round_finished_ms - round_started_ms ))"
    if (( round_status == 0 )); then
      append_ap_event "round-finished" "$worker_id" "$round" "completed" "$duration_ms" "$round_log"
    else
      append_ap_event "round-finished" "$worker_id" "$round" "failed" "$duration_ms" "$round_log"
      return "$round_status"
    fi

    if (( sleep_between_rounds > 0 )) && [[ $(date +%s) -lt $deadline_epoch ]]; then
      sleep "$sleep_between_rounds"
    fi
  done

  printf '%s\n' "$round" > "$worker_dir/rounds.txt"
}

start_ap_workers() {
  local deadline_epoch="$1"
  local sleep_between_rounds="$2"
  local terminals="${AP_TERMINALS:-${JOB_AP_TERMINALS:?missing JOB_AP_TERMINALS}}"
  AP_PIDS=()
  AP_TERMINALS_USED="$terminals"
  AP_BURST_INTERVAL_USED="$sleep_between_rounds"
  AP_RUNTIME_SECONDS_USED="$(( deadline_epoch - $(date +%s) ))"
  if (( AP_RUNTIME_SECONDS_USED < 0 )); then
    AP_RUNTIME_SECONDS_USED=0
  fi

  for ((worker_id = 1; worker_id <= terminals; worker_id++)); do
    run_ap_worker "$worker_id" "$deadline_epoch" "$sleep_between_rounds" &
    AP_PIDS+=("$!")
  done
}

wait_ap_workers() {
  local status=0
  local total_rounds=0
  local file rounds

  for pid in "${AP_PIDS[@]:-}"; do
    if [[ -n "$pid" ]] && ! wait "$pid"; then
      status=1
    fi
  done

  shopt -s nullglob
  for file in "$RUN_DIR"/ap/worker-*/rounds.txt; do
    rounds="$(tr -d '\r\n' < "$file")"
    total_rounds=$((total_rounds + rounds))
  done
  shopt -u nullglob

  AP_TOTAL_ROUNDS="$total_rounds"
  return "$status"
}

write_baseline_artifacts() {
  cat > "$RUN_DIR/derived/tp-baseline.json" <<EOF
{
  "rq": "${RQ:-P2MIX}",
  "dataset": "${DATASET:-job}",
  "tp_pressure": "${TP_PRESSURE:-unknown}",
  "cache_mode": "${CACHE_MODE:-warm}",
  "tp_driver": "${TP_DRIVER_USED:-pgbench}",
  "threads": "${TP_THREADS_USED:-unknown}",
  "terminals": "${TP_TERMINALS_USED:-unknown}",
  "rate_cap": "${TP_RATE_CAP_USED:-0}",
  "runtime_seconds": "${TP_RUNTIME_SECONDS_USED:-0}",
  "batch_size": "${JOB_TP_BATCH_SIZE:?missing JOB_TP_BATCH_SIZE}",
  "hot_modulus": "${JOB_TP_HOT_MODULUS:?missing JOB_TP_HOT_MODULUS}",
  "hot_remainder": "${JOB_TP_HOT_REMAINDER:?missing JOB_TP_HOT_REMAINDER}",
  "sql_file": "${TP_SQL_FILE_USED:-unknown-sql}",
  "progress_file": "${TP_PROGRESS_FILE_USED:-}",
  "summary_file": "${TP_SUMMARY_FILE_USED:-}",
  "status": "completed",
  "log_file": "$RUN_DIR/tp/freshness-updates.log"
}
EOF

  cat > "$RUN_DIR/derived/ap-baseline.json" <<EOF
{
  "rq": "${RQ:-P2MIX}",
  "dataset": "${DATASET:-job}",
  "ap_class": "${AP_CLASS:-sort-heavy}",
  "budget_tier": "${BUDGET_TIER:-moderate}",
  "terminals": "${AP_TERMINALS_USED:-${JOB_AP_TERMINALS:?missing JOB_AP_TERMINALS}}",
  "runtime_seconds": "${AP_RUNTIME_SECONDS_USED:-0}",
  "burst_interval_seconds": "${AP_BURST_INTERVAL_USED:-0}",
  "rounds_completed": "${AP_TOTAL_ROUNDS:-0}",
  "workload_drift_enabled": "${WORKLOAD_DRIFT_ENABLED_USED:-false}",
  "workload_drift_factor": "${WORKLOAD_DRIFT_FACTOR_USED:-0}",
  "workload_drift_realized_factor": "${WORKLOAD_DRIFT_REALIZED_FACTOR_USED:-0}",
  "status": "completed",
  "query_file": "${AP_QUERY_FILE_USED:-unknown-query}"
}
EOF

  cat > "$RUN_DIR/derived/mixed-baseline.json" <<EOF
{
  "rq": "${RQ:-P2MIX}",
  "dataset": "${DATASET:-job}",
  "budget_tier": "${BUDGET_TIER:-moderate}",
  "tp_pressure": "${TP_PRESSURE:-unknown}",
  "tp_driver": "${TP_DRIVER_USED:-pgbench}",
  "ap_class": "${AP_CLASS:-sort-heavy}",
  "overlap": "${WORKLOAD_OVERLAP_USED:-tp-first}",
  "warmup_seconds": "${WARMUP_SECONDS:-0}",
  "measure_seconds": "${MEASURE_SECONDS:-${DURATION_SECONDS:-60}}",
  "duration_seconds": "${DURATION_SECONDS:-60}",
  "tp_runtime_seconds": "${TP_RUNTIME_SECONDS_USED:-0}",
  "ap_runtime_seconds": "${AP_RUNTIME_SECONDS_USED:-0}",
  "tp_threads": "${TP_THREADS_USED:-unknown}",
  "tp_terminals": "${TP_TERMINALS_USED:-unknown}",
  "ap_terminals": "${AP_TERMINALS_USED:-${JOB_AP_TERMINALS:?missing JOB_AP_TERMINALS}}",
  "tp_sql_file": "${TP_SQL_FILE_USED:-unknown-sql}",
  "tp_progress_file": "${TP_PROGRESS_FILE_USED:-}",
  "tp_summary_file": "${TP_SUMMARY_FILE_USED:-}",
  "ap_query_file": "${AP_QUERY_FILE_USED:-unknown-query}",
  "ap_rounds_completed": "${AP_TOTAL_ROUNDS:-0}",
  "htap_check_type": "${HTAP_CHECK_TYPE_USED:-none}",
  "freshness_probe_id": "${FRESHNESS_PROBE_ID_USED:-}",
  "freshness_query_class": "${FRESHNESS_QUERY_CLASS_USED:-}",
  "freshness_target_range": "${FRESHNESS_TARGET_RANGE_USED:-}",
  "freshness_sample_count": "${FRESHNESS_SAMPLE_COUNT:-0}",
  "freshness_max_epoch_delta": "${FRESHNESS_MAX_EPOCH_DELTA:-0}",
  "freshness_latest_lag_ms": "${FRESHNESS_POST_LATEST_LAG_MS:-0}",
  "freshness_status": "${FRESHNESS_STATUS_USED:-not-requested}",
  "sync_latency_probe_id": "${SYNC_LATENCY_PROBE_ID_USED:-}",
  "sync_latency_query_class": "${SYNC_LATENCY_QUERY_CLASS_USED:-}",
  "sync_latency_target_range": "${SYNC_LATENCY_TARGET_RANGE_USED:-}",
  "sync_latency_target_movie_id": "${SYNC_LATENCY_TARGET_MOVIE_ID_USED:-}",
  "sync_latency_sample_count": "${SYNC_LATENCY_SAMPLE_COUNT:-0}",
  "sync_latency_max_ms": "${SYNC_LATENCY_MAX_LATENCY_MS:-0}",
  "sync_latency_post_mix_ms": "${SYNC_LATENCY_POST_LATENCY_MS:-0}",
  "sync_latency_status": "${SYNC_LATENCY_STATUS_USED:-not-requested}",
  "workload_drift_enabled": "${WORKLOAD_DRIFT_ENABLED_USED:-false}",
  "workload_drift_factor": "${WORKLOAD_DRIFT_FACTOR_USED:-0}",
  "workload_drift_realized_factor": "${WORKLOAD_DRIFT_REALIZED_FACTOR_USED:-0}",
  "workload_drift_base_class": "${WORKLOAD_DRIFT_BASE_CLASS_USED:-${AP_CLASS:-na}}",
  "workload_drift_sample_size": "${WORKLOAD_DRIFT_SAMPLE_SIZE_USED:-0}",
  "workload_drift_status": "${WORKLOAD_DRIFT_STATUS_USED:-not-requested}",
  "chaos_mode": "${CHAOS_MODE:-none}",
  "chaos_primitive": "${CHAOS_PRIMITIVE_USED:-none}",
  "chaos_status": "${CHAOS_STATUS_USED:-not-requested}",
  "chaos_wait_duration_ms": "${CHAOS_WAIT_DURATION_MS:-0}",
  "chaos_target_movie_id": "${CHAOS_TARGET_MOVIE_ID:-}",
  "chaos_deadlock_row_1_id": "${CHAOS_DEADLOCK_ROW_1_ID:-}",
  "chaos_deadlock_row_2_id": "${CHAOS_DEADLOCK_ROW_2_ID:-}",
  "chaos_deadlock_detected_count": "${CHAOS_DEADLOCK_DETECTED_COUNT:-0}",
  "chaos_deadlock_abort_count": "${CHAOS_DEADLOCK_ABORT_COUNT:-0}",
  "chaos_temp_files_delta": "${CHAOS_SPILL_TEMP_FILES_DELTA:-0}",
  "chaos_temp_bytes_delta": "${CHAOS_SPILL_TEMP_BYTES_DELTA:-0}",
  "chaos_spill_rate_qps": "${CHAOS_SPILL_EXECUTION_RATE_QPS:-0}",
  "status": "completed"
}
EOF
}

run_mixed_slice() {
  local overlap="${WORKLOAD_OVERLAP:-${OVERLAP:-tp-first}}"
  local warmup_seconds="${WARMUP_SECONDS:-0}"
  local duration_seconds="${DURATION_SECONDS:-60}"
  local tp_status=0
  local ap_status=0
  local chaos_status=0
  local deadline_epoch
  AP_QUERY_FILE_USED="$(resolve_ap_query)"
  WORKLOAD_OVERLAP_USED="$overlap"
  write_lifecycle_descriptor
  start_observability_sampler

  case "$overlap" in
    tp-first)
      prepare_tp_driver_settings "$((warmup_seconds + duration_seconds))"
      run_tp_driver "$TP_RUNTIME_SECONDS_USED" &
      TP_PID="$!"
      if [[ "$warmup_seconds" != "0" ]]; then
        sleep "$warmup_seconds"
      fi
      deadline_epoch=$(( $(date +%s) + duration_seconds ))
      start_ap_workers "$deadline_epoch" 0
      capture_lifecycle_boundary "$PHASE_PRE_INJECTION" "pre-injection" "pre-injection-ready"
      capture_lifecycle_boundary "$PHASE_DURING_INJECTION" "during-injection-start" "chaos-injection-start"
      if ! run_chaos_during_overlap "$deadline_epoch"; then
        chaos_status=1
      fi
      capture_lifecycle_boundary "$PHASE_POST_INJECTION" "post-injection-start" "chaos-injection-stop"
      if ! wait_ap_workers; then
        ap_status=1
      fi
      if ! wait "$TP_PID"; then
        tp_status=1
      fi
      ;;
    ap-first)
      deadline_epoch=$(( $(date +%s) + warmup_seconds + duration_seconds ))
      start_ap_workers "$deadline_epoch" 0
      if [[ "$warmup_seconds" != "0" ]]; then
        sleep "$warmup_seconds"
      fi
      prepare_tp_driver_settings "$duration_seconds"
      run_tp_driver "$TP_RUNTIME_SECONDS_USED" &
      TP_PID="$!"
      capture_lifecycle_boundary "$PHASE_PRE_INJECTION" "pre-injection" "pre-injection-ready"
      capture_lifecycle_boundary "$PHASE_DURING_INJECTION" "during-injection-start" "chaos-injection-start"
      if ! run_chaos_during_overlap "$deadline_epoch"; then
        chaos_status=1
      fi
      capture_lifecycle_boundary "$PHASE_POST_INJECTION" "post-injection-start" "chaos-injection-stop"
      if ! wait "$TP_PID"; then
        tp_status=1
      fi
      if ! wait_ap_workers; then
        ap_status=1
      fi
      ;;
    repeated-burst)
      prepare_tp_driver_settings "$((warmup_seconds + duration_seconds))"
      run_tp_driver "$TP_RUNTIME_SECONDS_USED" &
      TP_PID="$!"
      if [[ "$warmup_seconds" != "0" ]]; then
        sleep "$warmup_seconds"
      fi
      deadline_epoch=$(( $(date +%s) + duration_seconds ))
      start_ap_workers "$deadline_epoch" "${AP_BURST_INTERVAL_SECONDS:-5}"
      capture_lifecycle_boundary "$PHASE_PRE_INJECTION" "pre-injection" "pre-injection-ready"
      capture_lifecycle_boundary "$PHASE_DURING_INJECTION" "during-injection-start" "chaos-injection-start"
      if ! run_chaos_during_overlap "$deadline_epoch"; then
        chaos_status=1
      fi
      capture_lifecycle_boundary "$PHASE_POST_INJECTION" "post-injection-start" "chaos-injection-stop"
      if ! wait_ap_workers; then
        ap_status=1
      fi
      if ! wait "$TP_PID"; then
        tp_status=1
      fi
      ;;
    *)
      echo "unsupported WORKLOAD_OVERLAP: $overlap" >&2
      exit 1
      ;;
  esac

  capture_lifecycle_boundary "$PHASE_POST_INJECTION" "post-injection-end" "workload-finished"
  stop_observability_sampler
  write_freshness_artifacts
  write_sync_latency_artifacts

  if (( tp_status != 0 || ap_status != 0 || chaos_status != 0 )); then
    return 1
  fi
}

"$EXP_ROOT/scripts/prepare/00_env_sanity.sh" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/prepare/03_job_first_prepare.sh" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/prepare/01_dataset_snapshot_check.sh" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/prepare/02_adapter_capabilities.sh" --run-dir "$RUN_DIR"
AP_QUERY_FILE_USED="$(resolve_ap_query)"
PLAN_CAPTURE_QUERY_FILE="$AP_QUERY_FILE_USED"
if workload_drift_enabled; then
  PLAN_CAPTURE_QUERY_FILE="$(resolve_ap_query_for_class "${WORKLOAD_DRIFT_BASE_CLASS_USED:-${AP_CLASS:-sort-heavy}}")"
fi
"$EXP_ROOT/scripts/validation/30_plan_capture.sh" --run-dir "$RUN_DIR" --query-file "$PLAN_CAPTURE_QUERY_FILE"
run_mixed_slice
write_baseline_artifacts
"${HARNESS_EXPORT_RUN_ARTIFACTS:-$PROJECT_ROOT/scripts/harness_export_run_artifacts.sh}" --run-dir "$RUN_DIR"
"${PYTHON_BIN:-python}" "$EXP_ROOT/scripts/validation/40_recovery_check.py" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/validation/10_metrics_liveness.sh" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/validation/50_artifact_check.sh" --run-dir "$RUN_DIR" --phase in-run
if [[ "${AUTO_RENDER_PLOTS:-true}" == "true" ]]; then
  "${PLOT_PYTHON_BIN:-${PYTHON_BIN:-python}}" "$EXP_ROOT/scripts/analysis/render_mixed_run_plots.py" --run-dir "$RUN_DIR" || true
else
  cat > "$RUN_DIR/validation/plot-status.json" <<EOF
{
  "status": "skipped-disabled",
  "generated_files": [],
  "missing_inputs": []
}
EOF
fi
"${PYTHON_BIN:-python}" "$EXP_ROOT/scripts/validation/60_explainability_bundle.py" --run-dir "$RUN_DIR"
"${PYTHON_BIN:-python}" "$EXP_ROOT/scripts/analysis/export_run_sql_inventory.py" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/validation/50_artifact_check.sh" --run-dir "$RUN_DIR" --phase in-run
printf 'completed\n' > "$RUN_DIR/run-status.txt"
{
  cat <<EOF
- Mixed TP+AP baseline completed with overlap ${WORKLOAD_OVERLAP_USED:-tp-first}
- ${TP_DRIVER_USED:-pgbench} executed the generated TP template ${JOB_TP_TEMPLATE_ID:-unknown-template} from ${TP_SQL_FILE_USED:-unknown-sql}
- the AP class ${AP_CLASS:-sort-heavy} ran from ${AP_QUERY_FILE_USED:-unknown-query} with ${AP_TERMINALS_USED:-${JOB_AP_TERMINALS:?missing JOB_AP_TERMINALS}} terminals and ${AP_TOTAL_ROUNDS:-0} completed rounds
EOF
  if [[ "${HTAP_CHECK_TYPE_USED:-none}" == "query-oriented" ]]; then
    cat <<EOF
- query-oriented freshness probe ${FRESHNESS_PROBE_ID_USED:-unknown-probe} captured ${FRESHNESS_SAMPLE_COUNT:-0} samples on ${FRESHNESS_TARGET_RANGE_USED:-n/a}; max_epoch delta was ${FRESHNESS_MAX_EPOCH_DELTA:-0} and post-injection latest lag was ${FRESHNESS_POST_LATEST_LAG_MS:-0} ms
EOF
  elif [[ "${HTAP_CHECK_TYPE_USED:-none}" == "sync-latency" ]]; then
    cat <<EOF
- sync-latency probe ${SYNC_LATENCY_PROBE_ID_USED:-unknown-probe} captured ${SYNC_LATENCY_SAMPLE_COUNT:-0} samples on ${SYNC_LATENCY_TARGET_RANGE_USED:-n/a}; max sync latency was ${SYNC_LATENCY_MAX_LATENCY_MS:-0} ms and post-injection latency was ${SYNC_LATENCY_POST_LATENCY_MS:-0} ms on movie_id ${SYNC_LATENCY_TARGET_MOVIE_ID_USED:-n/a}
EOF
  fi
  if [[ "${WORKLOAD_DRIFT_ENABLED_USED:-false}" == "true" ]]; then
    cat <<EOF
- workload drift re-materialized the AP workload from base class ${WORKLOAD_DRIFT_BASE_CLASS_USED:-${AP_CLASS:-na}} with requested factor ${WORKLOAD_DRIFT_FACTOR_USED:-0}; realized factor was ${WORKLOAD_DRIFT_REALIZED_FACTOR_USED:-0} across ${WORKLOAD_DRIFT_SAMPLE_SIZE_USED:-0} sampled queries using ${AP_QUERY_FILE_USED:-unknown-query}
EOF
  fi
  if [[ "${CHAOS_PRIMITIVE_USED:-none}" == "wait_xact" ]]; then
    cat <<EOF
- chaos primitive ${CHAOS_PRIMITIVE_USED:-none} ran with status ${CHAOS_STATUS_USED:-unknown}; wait duration was ${CHAOS_WAIT_DURATION_MS:-0} ms on target movie_id ${CHAOS_TARGET_MOVIE_ID:-n/a}
EOF
  elif [[ "${CHAOS_PRIMITIVE_USED:-none}" == "deadlock_pair" ]]; then
    cat <<EOF
- chaos primitive ${CHAOS_PRIMITIVE_USED:-none} ran with status ${CHAOS_STATUS_USED:-unknown}; rows ${CHAOS_DEADLOCK_ROW_1_ID:-n/a} and ${CHAOS_DEADLOCK_ROW_2_ID:-n/a} produced ${CHAOS_DEADLOCK_DETECTED_COUNT:-0} detected deadlock error(s) with ${CHAOS_DEADLOCK_ABORT_COUNT:-0} aborted and ${CHAOS_DEADLOCK_COMMIT_COUNT:-0} committed sessions
EOF
  elif [[ "${CHAOS_PRIMITIVE_USED:-none}" == "spill_pressure" ]]; then
    cat <<EOF
- chaos primitive ${CHAOS_PRIMITIVE_USED:-none} ran with status ${CHAOS_STATUS_USED:-unknown}; temp_bytes delta was ${CHAOS_SPILL_TEMP_BYTES_DELTA:-0} with ${CHAOS_WORKERS_USED:-0} workers at ${CHAOS_RATE_USED:-0} qps and work_mem ${CHAOS_SESSION_MEMORY_USED:-n/a}
EOF
  elif [[ "${CHAOS_PRIMITIVE_USED:-none}" != "none" ]]; then
    cat <<EOF
- chaos primitive ${CHAOS_PRIMITIVE_USED:-none} ran with status ${CHAOS_STATUS_USED:-unknown}
EOF
  fi
} > "$RUN_DIR/explainability/top-findings.md"
