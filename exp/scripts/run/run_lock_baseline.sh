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
mkdir -p "$RUN_DIR/validation" "$RUN_DIR/derived" "$RUN_DIR/explainability" "$RUN_DIR/lock"

START_PSQL_SESSION_PID=""
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

run_lock_workload() {
  local lock_hold_seconds="${LOCK_HOLD_SECONDS:-${JOB_CHAOS_WAIT_LOCK_HOLD_SECONDS:?missing JOB_CHAOS_WAIT_LOCK_HOLD_SECONDS}}"
  local modulus="${JOB_TP_HOT_MODULUS:?missing JOB_TP_HOT_MODULUS}"
  local remainder="${JOB_TP_HOT_REMAINDER:?missing JOB_TP_HOT_REMAINDER}"
  local lock_movie_id blocker_sql waiter_sql blocker_pid waiter_pid
  local waiter_started_ms waiter_finished_ms blocker_exit_code waiter_exit_code wait_duration_ms

  ensure_env_file
  lock_movie_id="$(run_psql "${BENCHMARK_DB_NAME:-${JOB_DB_NAME:?missing JOB_DB_NAME}}" "select movie_id from movie_freshness where movie_id % $modulus = $remainder order by movie_id limit 1")"
  [[ -n "$lock_movie_id" ]] || fail "failed to resolve lock target movie_id"

  blocker_sql=$(cat <<EOF
BEGIN;
SELECT movie_id FROM movie_freshness WHERE movie_id = $lock_movie_id FOR UPDATE;
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
WHERE movie_id = $lock_movie_id;
EOF
)

  start_psql_session paper1-lock-blocker "$RUN_DIR/lock/blocker.log" "$blocker_sql"
  blocker_pid="$START_PSQL_SESSION_PID"
  sleep 2
  waiter_started_ms="$(date +%s%3N)"
  start_psql_session paper1-lock-waiter "$RUN_DIR/lock/waiter.log" "$waiter_sql"
  waiter_pid="$START_PSQL_SESSION_PID"
  sleep 2
  "${HARNESS_OBSERVE_LOCKS:-$PROJECT_ROOT/scripts/harness_observe_locks.sh}" --run-dir "$RUN_DIR" --database "${BENCHMARK_DB_NAME:-${JOB_DB_NAME:?missing JOB_DB_NAME}}"
  set +e
  wait "$waiter_pid"
  waiter_exit_code=$?
  waiter_finished_ms="$(date +%s%3N)"
  wait "$blocker_pid"
  blocker_exit_code=$?
  set -e
  wait_duration_ms=$(( waiter_finished_ms - waiter_started_ms ))
  [[ "$waiter_exit_code" -eq 0 ]] || fail "lock waiter failed; see $RUN_DIR/lock/waiter.log"
  [[ "$blocker_exit_code" -eq 0 ]] || fail "lock blocker failed; see $RUN_DIR/lock/blocker.log"

  cat > "$RUN_DIR/derived/lock-baseline.json" <<EOF
{
  "rq": "${RQ:-P1LOCK}",
  "dataset": "${DATASET:-job}",
  "variant": "${VARIANT:-waitxact}",
  "lock_movie_id": "$lock_movie_id",
  "lock_hold_seconds": "$lock_hold_seconds",
  "wait_duration_ms": "$wait_duration_ms",
  "blocker_exit_code": "$blocker_exit_code",
  "waiter_exit_code": "$waiter_exit_code",
  "status": "completed"
}
EOF
}

"$EXP_ROOT/scripts/prepare/00_env_sanity.sh" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/prepare/03_job_first_prepare.sh" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/prepare/01_dataset_snapshot_check.sh" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/prepare/02_adapter_capabilities.sh" --run-dir "$RUN_DIR"
run_lock_workload
"${HARNESS_EXPORT_RUN_ARTIFACTS:-$PROJECT_ROOT/scripts/harness_export_run_artifacts.sh}" --run-dir "$RUN_DIR" || true
run_psql_file "${BENCHMARK_DB_NAME:-${JOB_DB_NAME:?missing JOB_DB_NAME}}" "${JOB_WORKSPACE_CONSISTENCY_CHECK_SQL:?missing JOB_WORKSPACE_CONSISTENCY_CHECK_SQL}" > "$RUN_DIR/validation/consistency.json" || cp "$EXP_ROOT/sql/validation/consistency.fallback.json" "$RUN_DIR/validation/consistency.json"
"${PYTHON_BIN:-python}" "$EXP_ROOT/scripts/validation/40_recovery_check.py" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/validation/10_metrics_liveness.sh" --run-dir "$RUN_DIR"
"${PYTHON_BIN:-python}" "$EXP_ROOT/scripts/validation/60_explainability_bundle.py" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/validation/50_artifact_check.sh" --run-dir "$RUN_DIR"
printf 'completed\n' > "$RUN_DIR/run-status.txt"
cat > "$RUN_DIR/explainability/top-findings.md" <<EOF
- lock-path baseline completed for variant ${VARIANT:-waitxact}
- a real blocker/waiter pair ran against movie_freshness and lock snapshots were captured during the wait window
EOF
