#!/usr/bin/env bash
set -euo pipefail

RUN_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)
      RUN_DIR="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done
[[ -n "$RUN_DIR" ]] || { echo "--run-dir is required" >&2; exit 1; }
mkdir -p "$RUN_DIR/validation"

stat_database_alive=false
[[ -s "$RUN_DIR/observability/pg_stat_database.csv" ]] && stat_database_alive=true
stat_activity_alive=false
[[ -s "$RUN_DIR/observability/pg_stat_activity.csv" ]] && stat_activity_alive=true
lock_metrics_alive=false
[[ -s "$RUN_DIR/observability/pg_locks.csv" ]] && lock_metrics_alive=true

cat > "$RUN_DIR/validation/metrics-liveness.json" <<EOF
{
  "pg_stat_database_present": $stat_database_alive,
  "pg_stat_activity_present": $stat_activity_alive,
  "pg_locks_present": $lock_metrics_alive
}
EOF
