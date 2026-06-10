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
mkdir -p "$RUN_DIR/validation" "$RUN_DIR/derived" "$RUN_DIR/explainability" "$RUN_DIR/ap"

query_file="$(job_ap_query_file_for_class "$EXP_ROOT" "${AP_CLASS:-sort-heavy}")"

run_ap_loop() {
  local database="${BENCHMARK_DB_NAME:-${JOB_DB_NAME:?missing JOB_DB_NAME}}"
  local duration_seconds="${DURATION_SECONDS:-${JOB_DURATION_SECONDS:?missing JOB_DURATION_SECONDS}}"
  local warmup_seconds="${WARMUP_SECONDS:-0}"
  local pg_user="${AP_USER:-${BENCH_USER:-${DB_SUPERUSER:-postgres}}}"
  local pg_password="${AP_PASSWORD:-${BENCH_PASSWORD:-${DB_SUPERUSER_PASSWORD:-postgres}}}"
  local sql_body ap_parallelism
  local deadline round round_log

  ensure_env_file
  sql_body="$(cat "$query_file")"
  ap_parallelism="${AP_PARALLELISM:-0}"
  if [[ "$ap_parallelism" =~ ^[0-9]+$ ]] && (( ap_parallelism > 0 )); then
    sql_body=$(cat <<EOF
SET max_parallel_workers_per_gather = ${ap_parallelism};
${sql_body}
EOF
)
  fi
  if [[ "$warmup_seconds" != "0" ]]; then
    sleep "$warmup_seconds"
  fi
  deadline=$(( $(date +%s) + duration_seconds ))
  round=0
  while [[ $(date +%s) -lt $deadline ]]; do
    round=$((round + 1))
    round_log="$RUN_DIR/ap/round-$(printf '%03d' "$round").log"
    if is_source_runtime; then
      printf '%s\n' "$sql_body" | \
        PGPASSWORD="$pg_password" \
        PGAPPNAME="${PGAPPNAME:-paper1-ap}" \
        "$(source_pg_bin_dir)/psql" \
        -h "$(source_pg_host)" \
        -p "$(source_pg_port)" \
        -U "$pg_user" \
        -d "$database" \
        -v ON_ERROR_STOP=1 > "$round_log" 2>&1
    else
      printf '%s\n' "$sql_body" | \
        compose exec -T \
          -e PGAPPNAME="${PGAPPNAME:-paper1-ap}" \
          -e PGPASSWORD="$pg_password" \
          "${DB_SERVICE_NAME:-postgres}" \
          psql -h 127.0.0.1 -U "$pg_user" -d "$database" -v ON_ERROR_STOP=1 > "$round_log" 2>&1
    fi
  done

  cat > "$RUN_DIR/derived/ap-baseline.json" <<EOF
{
  "rq": "${RQ:-P1AP}",
  "dataset": "${DATASET:-job}",
  "ap_class": "${AP_CLASS:-sort-heavy}",
  "budget_tier": "${BUDGET_TIER:-moderate}",
  "duration_seconds": "$duration_seconds",
  "rounds_completed": "$round",
  "status": "completed",
  "query_file": "$query_file"
}
EOF
}

"$EXP_ROOT/scripts/prepare/00_env_sanity.sh" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/prepare/03_job_first_prepare.sh" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/prepare/01_dataset_snapshot_check.sh" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/prepare/02_adapter_capabilities.sh" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/validation/30_plan_capture.sh" --run-dir "$RUN_DIR" --query-file "$query_file"
run_ap_loop
"${HARNESS_EXPORT_RUN_ARTIFACTS:-$PROJECT_ROOT/scripts/harness_export_run_artifacts.sh}" --run-dir "$RUN_DIR" || true
"$EXP_ROOT/scripts/validation/10_metrics_liveness.sh" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/validation/50_artifact_check.sh" --run-dir "$RUN_DIR"
"${PYTHON_BIN:-python}" "$EXP_ROOT/scripts/validation/60_explainability_bundle.py" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/validation/50_artifact_check.sh" --run-dir "$RUN_DIR"
printf 'completed\n' > "$RUN_DIR/run-status.txt"
cat > "$RUN_DIR/explainability/top-findings.md" <<EOF
- AP-only baseline completed for class ${AP_CLASS:-sort-heavy}
- the selected JOB-first AP query was executed repeatedly for ${DURATION_SECONDS:-${JOB_DURATION_SECONDS:?missing JOB_DURATION_SECONDS}} seconds
EOF
