#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/harness_common.sh"

RUN_DIR=""
DATABASE="${BENCHMARK_DB_NAME:-postgres}"
PG_ACTIVITY_ENABLED="${OBSERVE_PG_ACTIVITY_ENABLED:-false}"
PG_ACTIVITY_TIMEOUT_SECONDS="${OBSERVE_PG_ACTIVITY_TIMEOUT_SECONDS:-3}"
PG_ACTIVITY_REFRESH_SECONDS="${OBSERVE_PG_ACTIVITY_REFRESH_SECONDS:-1}"
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
[[ "$PG_ACTIVITY_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || fail "OBSERVE_PG_ACTIVITY_TIMEOUT_SECONDS must be an integer"
[[ "$PG_ACTIVITY_REFRESH_SECONDS" =~ ^[0-9]+$ ]] || fail "OBSERVE_PG_ACTIVITY_REFRESH_SECONDS must be an integer"
mkdir -p "$RUN_DIR/observability"

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

relation_exists() {
  local relname="$1"
  [[ "$(run_psql "$DATABASE" "select to_regclass('$relname') is not null")" == "t" ]]
}

function_exists() {
  local funcname="$1"
  [[ "$(run_psql "$DATABASE" "select exists(select 1 from pg_proc where proname = '$funcname')")" == "t" ]]
}

write_pg_activity_export_status() {
  ${PYTHON_BIN:-python} - "$RUN_DIR/observability/pg_activity.final.json" "$1" "$2" "$3" "$4" "$5" "$DATABASE" "$PG_ACTIVITY_TIMEOUT_SECONDS" "$PG_ACTIVITY_REFRESH_SECONDS" <<'PY'
import json
import sys
from pathlib import Path

output_path = Path(sys.argv[1])
report = {
    "status": sys.argv[2],
    "output_file": sys.argv[3],
    "stderr_file": sys.argv[4],
    "row_count": int(sys.argv[5]),
    "exit_code": int(sys.argv[6]),
    "database": sys.argv[7],
    "timeout_seconds": int(sys.argv[8]),
    "refresh_seconds": int(sys.argv[9]),
}
output_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
}

capture_pg_activity_final_snapshot() {
  local output_file="$RUN_DIR/observability/pg_activity.final.csv"
  local stderr_file="${output_file}.stderr.txt"
  local capture_timeout="$PG_ACTIVITY_TIMEOUT_SECONDS"
  local row_count="0"
  local status="skipped-disabled"
  local exit_code="0"

  if [[ "$PG_ACTIVITY_ENABLED" != "true" ]]; then
    write_pg_activity_export_status "$status" "$output_file" "" "$row_count" "$exit_code"
    return 0
  fi

  if (( capture_timeout <= PG_ACTIVITY_REFRESH_SECONDS )); then
    capture_timeout=$((PG_ACTIVITY_REFRESH_SECONDS + 1))
  fi

  set +e
  run_pg_activity_capture "$output_file" "$capture_timeout" "$DATABASE" "${DB_SUPERUSER:-postgres}" "${DB_SUPERUSER_PASSWORD:-postgres}"
  exit_code=$?
  set -e

  if [[ -f "$output_file" ]]; then
    row_count="$(${PYTHON_BIN:-python} - "$output_file" <<'PY'
import csv
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    with path.open(encoding="utf-8", errors="ignore", newline="") as fh:
        rows = list(csv.reader(fh))
except Exception:
    print("0")
    raise SystemExit(0)
print(max(len(rows) - 1, 0))
PY
)"
    status="captured"
    if [[ "$row_count" == "0" ]]; then
      status="empty"
    fi
  else
    status="failed"
  fi

  if (( exit_code != 0 )) && [[ "$status" == "captured" ]]; then
    status="captured-with-nonzero-exit"
  fi
  if (( exit_code != 0 )) && [[ "$status" == "empty" ]]; then
    status="failed"
  fi
  if [[ ! -f "$stderr_file" ]]; then
    stderr_file=""
  fi

  write_pg_activity_export_status "$status" "$output_file" "$stderr_file" "$row_count" "$exit_code"
}

log "exporting PostgreSQL stats into $RUN_DIR/observability"
psql_copy "select extname, extversion from pg_extension order by extname" "$RUN_DIR/observability/pg_extension.csv"
psql_copy "select name, setting, unit, source, boot_val, reset_val from pg_settings order by name" "$RUN_DIR/observability/pg_settings.csv"
psql_copy "select datname, numbackends, xact_commit, xact_rollback, blks_read, blks_hit, tup_returned, tup_fetched, tup_inserted, tup_updated, tup_deleted, temp_files, temp_bytes, deadlocks from pg_stat_database order by datname" "$RUN_DIR/observability/pg_stat_database.csv"
psql_copy "select pid, usename, application_name, datname, state, wait_event_type, wait_event, backend_type, xact_start, query_start from pg_stat_activity order by pid" "$RUN_DIR/observability/pg_stat_activity.csv"
psql_copy "select locktype, database, relation, page, tuple, virtualxid, transactionid, classid, objid, objsubid, virtualtransaction, pid, mode, granted, fastpath, waitstart from pg_locks order by pid, locktype, mode" "$RUN_DIR/observability/pg_locks.csv"

if relation_exists 'pg_stat_bgwriter'; then
  psql_copy "select * from pg_stat_bgwriter" "$RUN_DIR/observability/pg_stat_bgwriter.csv"
fi

if relation_exists 'pg_stat_wal'; then
  psql_copy "select * from pg_stat_wal" "$RUN_DIR/observability/pg_stat_wal.csv"
fi

if relation_exists 'pg_stat_io'; then
  psql_copy "select * from pg_stat_io order by backend_type, object, context" "$RUN_DIR/observability/pg_stat_io.csv"
fi

if relation_exists 'pg_wait_sampling_profile'; then
  psql_copy "select * from pg_wait_sampling_profile" "$RUN_DIR/observability/pg_wait_sampling_profile.csv"
fi

if relation_exists 'pg_buffercache'; then
  psql_copy "with current_db as (select oid as db_oid from pg_database where datname = current_database()) select count(*) filter (where reldatabase in (0, (select db_oid from current_db))) as db_cached_buffers, round((count(*) filter (where reldatabase in (0, (select db_oid from current_db))) * current_setting('block_size')::bigint)::numeric / 1048576, 3) as db_cached_mb, count(*) filter (where reldatabase in (0, (select db_oid from current_db)) and isdirty) as db_dirty_buffers, round((count(*) filter (where reldatabase in (0, (select db_oid from current_db)) and isdirty) * current_setting('block_size')::bigint)::numeric / 1048576, 3) as db_dirty_mb, coalesce(sum(pinning_backends),0) as pinned_backends, round(coalesce(avg(usagecount),0)::numeric, 3) as avg_usagecount from pg_buffercache" "$RUN_DIR/observability/pg_buffercache_summary.csv"
fi

if relation_exists 'pg_stat_statements'; then
  psql_copy "select userid, dbid, toplevel, queryid, calls, total_exec_time, rows, shared_blks_hit, shared_blks_read, temp_blks_read, temp_blks_written from pg_stat_statements" "$RUN_DIR/observability/pg_stat_statements.csv"
fi

if relation_exists 'pg_stat_kcache'; then
  psql_copy "select * from pg_stat_kcache" "$RUN_DIR/observability/pg_stat_kcache.csv"
fi

if function_exists 'pg_sys_memory_info'; then
  psql_copy "select round(coalesce(total_memory,0)::numeric / 1048576, 3) as system_total_mb, round(coalesce(used_memory,0)::numeric / 1048576, 3) as system_used_mb, round(coalesce(free_memory,0)::numeric / 1048576, 3) as system_free_mb, round(coalesce(cache_total,0)::numeric / 1048576, 3) as system_cache_mb, round(coalesce(swap_total,0)::numeric / 1048576, 3) as swap_total_mb, round(coalesce(swap_used,0)::numeric / 1048576, 3) as swap_used_mb, round(coalesce(swap_free,0)::numeric / 1048576, 3) as swap_free_mb from pg_sys_memory_info()" "$RUN_DIR/observability/system_stats_memory.csv"
fi

if function_exists 'pg_sys_cpu_memory_by_process'; then
  psql_copy "select a.pid, a.backend_type, a.datname, a.usename, a.application_name, round(coalesce(p.running_since_seconds,0)::numeric, 3) as running_since_seconds, round(coalesce(p.cpu_usage,0)::numeric, 3) as cpu_usage, round(coalesce(p.memory_usage,0)::numeric, 3) as memory_usage, round(coalesce(p.memory_bytes,0)::numeric / 1048576, 3) as memory_mb from pg_stat_activity a join pg_sys_cpu_memory_by_process() p on p.pid = a.pid order by round(coalesce(p.memory_bytes,0)::numeric / 1048576, 3) desc, a.pid" "$RUN_DIR/observability/system_stats_backend_memory.csv"
fi

capture_pg_activity_final_snapshot
