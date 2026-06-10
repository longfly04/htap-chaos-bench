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
mkdir -p "$RUN_DIR/validation" "$RUN_DIR/derived" "$RUN_DIR/explainability" "$RUN_DIR/tp"
TP_SQL_FILE_USED=""
TP_THREADS_USED=""
TP_TERMINALS_USED=""
TP_RATE_CAP_USED=""
TP_DRIVER_USED=""
TP_RUNTIME_SECONDS_USED=""
TP_LOG_FILE_USED=""
TP_PROGRESS_FILE_USED=""
TP_SUMMARY_FILE_USED=""
TP_SYSBENCH_SCRIPT_USED=""

threads_for_pressure() {
  job_tp_threads_for_pressure "${TP_PRESSURE:-medium}"
}

prepare_tp_driver_settings() {
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
  TP_RUNTIME_SECONDS_USED="${DURATION_SECONDS:-${JOB_DURATION_SECONDS:?missing JOB_DURATION_SECONDS}}"
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

run_tp_pgbench() {
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
    PGPASSWORD="$pg_password" PGAPPNAME="${PGAPPNAME:-paper1-jobtp}" "$(source_pg_bin_dir)/pgbench" \
      -h "$(source_pg_host)" \
      -p "$(source_pg_port)" \
      -U "$pg_user" \
      -d "$database" \
      --client "$TP_TERMINALS_USED" \
      --jobs "$TP_THREADS_USED" \
      --time "$TP_RUNTIME_SECONDS_USED" \
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
      -e PGAPPNAME="${PGAPPNAME:-paper1-jobtp}" \
      -e PGPASSWORD="$pg_password" \
      "${DB_SERVICE_NAME:-postgres}" \
      pgbench -h 127.0.0.1 -p 5432 -U "$pg_user" -d "$database" \
      --client "$TP_TERMINALS_USED" \
      --jobs "$TP_THREADS_USED" \
      --time "$TP_RUNTIME_SECONDS_USED" \
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
  PGPASSWORD="$pg_password" PGAPPNAME="${PGAPPNAME:-paper1-jobtp}" "$sysbench_path" \
    --db-driver=pgsql \
    --pgsql-host="$pg_host" \
    --pgsql-port="$pg_port" \
    --pgsql-user="$pg_user" \
    --pgsql-password="$pg_password" \
    --pgsql-db="$database" \
    --threads="$TP_TERMINALS_USED" \
    --time="$TP_RUNTIME_SECONDS_USED" \
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
  prepare_tp_driver_settings
  case "$TP_DRIVER_USED" in
    pgbench)
      run_tp_pgbench
      ;;
    sysbench)
      run_tp_sysbench
      ;;
  esac

  cat > "$RUN_DIR/derived/tp-baseline.json" <<EOF
{
  "rq": "${RQ:-P1TP}",
  "dataset": "${DATASET:-job}",
  "tp_pressure": "${TP_PRESSURE:-unknown}",
  "cache_mode": "${CACHE_MODE:-warm}",
  "tp_driver": "$TP_DRIVER_USED",
  "threads": "$TP_THREADS_USED",
  "terminals": "$TP_TERMINALS_USED",
  "rate_cap": "$TP_RATE_CAP_USED",
  "duration_seconds": "$TP_RUNTIME_SECONDS_USED",
  "batch_size": "${JOB_TP_BATCH_SIZE:?missing JOB_TP_BATCH_SIZE}",
  "hot_modulus": "${JOB_TP_HOT_MODULUS:?missing JOB_TP_HOT_MODULUS}",
  "hot_remainder": "${JOB_TP_HOT_REMAINDER:?missing JOB_TP_HOT_REMAINDER}",
  "sql_file": "$TP_SQL_FILE_USED",
  "progress_file": "$TP_PROGRESS_FILE_USED",
  "summary_file": "$TP_SUMMARY_FILE_USED",
  "status": "completed",
  "log_file": "$TP_LOG_FILE_USED"
}
EOF
}

"$EXP_ROOT/scripts/prepare/00_env_sanity.sh" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/prepare/03_job_first_prepare.sh" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/prepare/01_dataset_snapshot_check.sh" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/prepare/02_adapter_capabilities.sh" --run-dir "$RUN_DIR"
run_tp_driver
"${HARNESS_EXPORT_RUN_ARTIFACTS:-$PROJECT_ROOT/scripts/harness_export_run_artifacts.sh}" --run-dir "$RUN_DIR" || true
"$EXP_ROOT/scripts/validation/10_metrics_liveness.sh" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/validation/50_artifact_check.sh" --run-dir "$RUN_DIR"
"${PYTHON_BIN:-python}" "$EXP_ROOT/scripts/validation/60_explainability_bundle.py" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/validation/50_artifact_check.sh" --run-dir "$RUN_DIR"
printf 'completed\n' > "$RUN_DIR/run-status.txt"
cat > "$RUN_DIR/explainability/top-findings.md" <<EOF
- TP-only baseline completed for pressure ${TP_PRESSURE:-unknown}
- ${TP_DRIVER_USED:-pgbench} executed the TP template ${JOB_TP_TEMPLATE_ID:-unknown-template} from ${TP_SQL_FILE_USED:-unknown-sql} against ${BENCHMARK_DB_NAME:-${JOB_DB_NAME:?missing JOB_DB_NAME}}
- driver settings used ${TP_TERMINALS_USED:-unknown-terminals} terminals, ${TP_THREADS_USED:-unknown-threads} worker threads, and rate cap ${TP_RATE_CAP_USED:-0}
EOF
