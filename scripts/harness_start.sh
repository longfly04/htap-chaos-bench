#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/harness_common.sh"

APPLY_SQL_FILES=()
TARGET_DB_NAME="${DB_NAME:-benchdb}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply-sql)
      APPLY_SQL_FILES+=("$2")
      shift 2
      ;;
    --database)
      TARGET_DB_NAME="$2"
      shift 2
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

ensure_env_file
BENCH_USER="${BENCH_USER:-${DB_SUPERUSER:-postgres}}"
BENCH_PASSWORD="${BENCH_PASSWORD:-postgres}"
OBSERVABILITY_SQL_FILE="${OBSERVABILITY_SQL_FILE:-$PROJECT_WORKSPACE_SQL_ROOT/observability/install_views.sql}"

append_preload_library() {
  local current="$1"
  local library_name="$2"
  if [[ -z "$library_name" ]]; then
    printf '%s' "$current"
    return
  fi
  case ",$current," in
    *,"$library_name",*)
      printf '%s' "$current"
      ;;
    ,,)
      printf '%s' "$library_name"
      ;;
    *)
      printf '%s,%s' "$current" "$library_name"
      ;;
  esac
}

shared_preload_libraries_used="${POSTGRES_SHARED_PRELOAD_LIBRARIES:-pg_stat_statements}"
if [[ "${INSTALL_OBSERVABILITY_EXTENSIONS:-false}" == "true" ]]; then
  for extension_name in ${OBSERVABILITY_EXTENSION_SOURCE_NAMES//,/ }; do
    case "$extension_name" in
      pg_wait_sampling|pg_stat_monitor|pg_stat_kcache)
        shared_preload_libraries_used="$(append_preload_library "$shared_preload_libraries_used" "$extension_name")"
        ;;
    esac
  done
fi

if is_source_runtime; then
  "${HARNESS_INSTALL_OBSERVABILITY_EXTENSIONS:-$SCRIPT_DIR/harness_install_observability_extensions.sh}"
  bindir="$(source_pg_bin_dir)"
  runtime_dir="${SOURCE_PG_RUNTIME_DIR:-$LAB_ROOT/runs/.source-pg-runtime}"
  data_dir="$runtime_dir/data"
  socket_dir="$runtime_dir/socket"
  log_file="$runtime_dir/postgres.log"
  conf_file="$data_dir/source-runtime.conf"
  ensure_cmd "$bindir/psql"
  ensure_cmd "$bindir/pg_ctl"
  ensure_cmd "$bindir/initdb"
  ensure_cmd "$bindir/pg_isready"
  mkdir -p "$runtime_dir" "$socket_dir"
  if [[ ! -f "$data_dir/PG_VERSION" ]]; then
    log "initializing source-built PostgreSQL runtime data directory"
    "$bindir/initdb" -D "$data_dir" -U "$(source_pg_user)" -A trust >/dev/null
    if ! grep -q "include_if_exists = 'source-runtime.conf'" "$data_dir/postgresql.conf"; then
      printf "\ninclude_if_exists = 'source-runtime.conf'\n" >> "$data_dir/postgresql.conf"
    fi
  fi
  cat > "$conf_file" <<EOF
listen_addresses = '127.0.0.1'
port = $(source_pg_port)
unix_socket_directories = '$socket_dir'
shared_buffers = ${POSTGRES_SHARED_BUFFERS:-256MB}
effective_cache_size = ${POSTGRES_EFFECTIVE_CACHE_SIZE:-1GB}
work_mem = ${POSTGRES_WORK_MEM:-8MB}
maintenance_work_mem = ${POSTGRES_MAINTENANCE_WORK_MEM:-128MB}
checkpoint_completion_target = ${POSTGRES_CHECKPOINT_COMPLETION_TARGET:-0.9}
wal_buffers = ${POSTGRES_WAL_BUFFERS:-16MB}
default_statistics_target = ${POSTGRES_DEFAULT_STATISTICS_TARGET:-100}
random_page_cost = ${POSTGRES_RANDOM_PAGE_COST:-1.1}
effective_io_concurrency = ${POSTGRES_EFFECTIVE_IO_CONCURRENCY:-200}
huge_pages = ${POSTGRES_HUGE_PAGES:-off}
jit = ${POSTGRES_JIT:-off}
wal_compression = ${POSTGRES_WAL_COMPRESSION:-on}
autovacuum_max_workers = ${POSTGRES_AUTOVACUUM_MAX_WORKERS:-3}
min_wal_size = ${POSTGRES_MIN_WAL_SIZE:-80MB}
max_wal_size = ${POSTGRES_MAX_WAL_SIZE:-1GB}
max_worker_processes = ${POSTGRES_MAX_WORKER_PROCESSES:-8}
max_parallel_workers_per_gather = ${POSTGRES_MAX_PARALLEL_WORKERS_PER_GATHER:-2}
max_parallel_workers = ${POSTGRES_MAX_PARALLEL_WORKERS:-8}
max_parallel_maintenance_workers = ${POSTGRES_MAX_PARALLEL_MAINTENANCE_WORKERS:-2}
temp_file_limit = ${POSTGRES_TEMP_FILE_LIMIT:--1}
max_connections = ${POSTGRES_MAX_CONNECTIONS:-200}
log_temp_files = 0
logging_collector = off
log_destination = 'stderr'
log_line_prefix = '%m [%p] %q%u@%d'
shared_preload_libraries = '${shared_preload_libraries_used}'
track_io_timing = on
track_functions = all
track_activity_query_size = 4096
EOF
  if "$bindir/pg_ctl" -D "$data_dir" status >/dev/null 2>&1; then
    log "restarting source-built PostgreSQL runtime"
    "$bindir/pg_ctl" -D "$data_dir" -m fast stop -w >/dev/null || true
  fi
  log "starting source-built PostgreSQL runtime"
  "$bindir/pg_ctl" -D "$data_dir" -l "$log_file" start -w >/dev/null
  wait_for_db 120 2
  run_psql postgres "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$BENCH_USER') THEN EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', '$BENCH_USER', '$BENCH_PASSWORD'); END IF; END \$\$;"
  if [[ "$(run_psql postgres "select count(*) from pg_database where datname = '$TARGET_DB_NAME'")" == "0" ]]; then
    run_psql postgres "CREATE DATABASE \"$TARGET_DB_NAME\" OWNER \"$BENCH_USER\""
  fi
  if [[ -n "$OBSERVABILITY_SQL_FILE" ]]; then
    run_psql_file "$TARGET_DB_NAME" "$OBSERVABILITY_SQL_FILE"
  fi
  if [[ ${#APPLY_SQL_FILES[@]} -gt 0 ]]; then
    for apply_sql_file in "${APPLY_SQL_FILES[@]}"; do
      run_psql_file "$TARGET_DB_NAME" "$apply_sql_file"
    done
  fi
  log "source-built PostgreSQL lab is ready"
  exit 0
fi

ensure_cmd docker
log "starting PostgreSQL lab"
compose up -d "${DB_SERVICE_NAME:-postgres}"
wait_for_db
if [[ "$(run_psql postgres "select count(*) from pg_database where datname = '$TARGET_DB_NAME'")" == "0" ]]; then
  run_psql postgres "CREATE DATABASE \"$TARGET_DB_NAME\" OWNER \"$BENCH_USER\""
fi
if [[ -n "$OBSERVABILITY_SQL_FILE" ]]; then
  run_psql_file "$TARGET_DB_NAME" "$OBSERVABILITY_SQL_FILE"
fi
if [[ ${#APPLY_SQL_FILES[@]} -gt 0 ]]; then
  for apply_sql_file in "${APPLY_SQL_FILES[@]}"; do
    run_psql_file "$TARGET_DB_NAME" "$apply_sql_file"
  done
fi
log "PostgreSQL lab is ready"
