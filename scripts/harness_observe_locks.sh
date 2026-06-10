#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/harness_common.sh"

RUN_DIR=""
DATABASE="${BENCHMARK_DB_NAME:-postgres}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)
      RUN_DIR="$2"
      shift 2
      ;;
    --database)
      DATABASE="$2"
      shift 2
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done
[[ -n "$RUN_DIR" ]] || fail "--run-dir is required"
mkdir -p "$RUN_DIR/observability"

psql_text() {
  local sql="$1"
  if is_source_runtime; then
    local psql_bin
    psql_bin="$(source_pg_bin_dir)/psql"
    PGPASSWORD="${DB_SUPERUSER_PASSWORD:-postgres}" "$psql_bin" -h "$(source_pg_host)" -p "$(source_pg_port)" -U "$(source_pg_user)" -d "$DATABASE" -v ON_ERROR_STOP=1 -P pager=off -c "$sql"
    return
  fi
  compose exec -T -e PGPASSWORD="${DB_SUPERUSER_PASSWORD:-postgres}" "${DB_SERVICE_NAME:-postgres}" psql -h 127.0.0.1 -U "${DB_SUPERUSER:-postgres}" -d "$DATABASE" -v ON_ERROR_STOP=1 -P pager=off -c "$sql"
}

psql_copy() {
  local query="$1"
  local output_path="$2"
  if is_source_runtime; then
    local psql_bin
    psql_bin="$(source_pg_bin_dir)/psql"
    PGPASSWORD="${DB_SUPERUSER_PASSWORD:-postgres}" "$psql_bin" -h "$(source_pg_host)" -p "$(source_pg_port)" -U "$(source_pg_user)" -d "$DATABASE" -v ON_ERROR_STOP=1 -c "\\copy ($query) TO STDOUT WITH CSV HEADER" > "$output_path"
    return
  fi
  compose exec -T -e PGPASSWORD="${DB_SUPERUSER_PASSWORD:-postgres}" "${DB_SERVICE_NAME:-postgres}" psql -h 127.0.0.1 -U "${DB_SUPERUSER:-postgres}" -d "$DATABASE" -v ON_ERROR_STOP=1 -c "\\copy ($query) TO STDOUT WITH CSV HEADER" > "$output_path"
}

log "capturing lock snapshot into $RUN_DIR/observability"
psql_copy "select a.pid, a.usename, a.datname, a.state, a.wait_event_type, a.wait_event, a.xact_start, l.locktype, l.relation, l.mode, l.granted, l.fastpath, l.waitstart from pg_stat_activity a left join pg_locks l on a.pid = l.pid order by a.pid, l.locktype, l.mode" "$RUN_DIR/observability/lock-snapshot.csv"
psql_text "select pid, pg_blocking_pids(pid) as blockers, wait_event_type, wait_event, state, query_start from pg_stat_activity where cardinality(pg_blocking_pids(pid)) > 0 order by query_start nulls last;" > "$RUN_DIR/observability/blocking-tree.txt" || true
