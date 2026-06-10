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

RUN_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)
      RUN_DIR="$2"
      shift 2
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done
[[ -n "$RUN_DIR" ]] || fail "--run-dir is required"

JOB_DB_NAME="${BENCHMARK_DB_NAME:-${JOB_DB_NAME:?missing JOB_DB_NAME}}"
JOB_IMPORT_SCHEMA_FILE="${JOB_IMPORT_SCHEMA_FILE:-}"
JOB_IMPORT_LOAD_FILE="${JOB_IMPORT_LOAD_FILE:-}"
JOB_IMPORT_FKINDEX_FILE="${JOB_IMPORT_FKINDEX_FILE:-}"
JOB_CSV_BASE_DIR="${JOB_CSV_BASE_DIR:-}"
JOB_IMPORT_LOAD_PLACEHOLDER_ROOT="${JOB_IMPORT_LOAD_PLACEHOLDER_ROOT:-}"
JOB_DB_LOAD_POLICY="${JOB_DB_LOAD_POLICY:-reuse_if_present}"
JOB_TP_HOT_MODULUS="${JOB_TP_HOT_MODULUS:?missing JOB_TP_HOT_MODULUS}"
JOB_TP_HOT_REMAINDER="${JOB_TP_HOT_REMAINDER:-$(( ${SEED:-1} % JOB_TP_HOT_MODULUS ))}"
JOB_OUT_DIR="$RUN_DIR/job-first"
mkdir -p "$JOB_OUT_DIR"
ensure_env_file

if is_source_runtime; then
  HOST_PSQL_PORT="$(source_pg_port)"
else
  HOST_PSQL_PORT="${DB_PORT:-55437}"
fi
HOST_PSQL_USER="${DB_SUPERUSER:-postgres}"
HOST_PSQL_PASSWORD="${DB_SUPERUSER_PASSWORD:-postgres}"
HOST_PSQL_BIN="$(source_pg_bin_dir)/psql"
[[ -x "$HOST_PSQL_BIN" ]] || fail "psql binary not found: $HOST_PSQL_BIN"

if [[ "$JOB_DB_LOAD_POLICY" == "reload" ]]; then
  [[ -n "$JOB_IMPORT_SCHEMA_FILE" ]] || fail "JOB_IMPORT_SCHEMA_FILE is required when JOB_DB_LOAD_POLICY=reload"
  [[ -n "$JOB_IMPORT_LOAD_FILE" ]] || fail "JOB_IMPORT_LOAD_FILE is required when JOB_DB_LOAD_POLICY=reload"
  [[ -n "$JOB_IMPORT_FKINDEX_FILE" ]] || fail "JOB_IMPORT_FKINDEX_FILE is required when JOB_DB_LOAD_POLICY=reload"
  [[ -n "$JOB_CSV_BASE_DIR" ]] || fail "JOB_CSV_BASE_DIR is required when JOB_DB_LOAD_POLICY=reload"
  [[ -n "$JOB_IMPORT_LOAD_PLACEHOLDER_ROOT" ]] || fail "JOB_IMPORT_LOAD_PLACEHOLDER_ROOT is required when JOB_DB_LOAD_POLICY=reload"
  run_psql postgres "DROP DATABASE IF EXISTS \"$JOB_DB_NAME\";"
fi
if [[ "$(run_psql postgres "select count(*) from pg_database where datname = '$JOB_DB_NAME'")" == "0" ]]; then
  run_psql postgres "CREATE DATABASE \"$JOB_DB_NAME\" OWNER \"${BENCH_USER:-bench}\""
fi

run_psql_file "$JOB_DB_NAME" "$JOB_WORKSPACE_INSTALL_VIEWS_SQL" > "$JOB_OUT_DIR/install-observability.log" 2>&1

if [[ "$JOB_DB_LOAD_POLICY" == "reload" ]]; then
  rewritten_load_sql="$JOB_OUT_DIR/load_sql.rewritten.sql"
  "${PYTHON_BIN:-python}" - "$JOB_IMPORT_LOAD_FILE" "$rewritten_load_sql" "$JOB_CSV_BASE_DIR" "$JOB_IMPORT_LOAD_PLACEHOLDER_ROOT" <<'PY'
import sys
from pathlib import Path
src = Path(sys.argv[1]).read_text(encoding='utf-8')
base = sys.argv[3].rstrip('/')
placeholder = sys.argv[4].rstrip('/')
src = src.replace(placeholder, base)
Path(sys.argv[2]).write_text(src, encoding='utf-8')
PY
  PGPASSWORD="$HOST_PSQL_PASSWORD" "$HOST_PSQL_BIN" -h 127.0.0.1 -p "$HOST_PSQL_PORT" -U "$HOST_PSQL_USER" -d "$JOB_DB_NAME" -v ON_ERROR_STOP=1 -f "$JOB_IMPORT_SCHEMA_FILE" > "$JOB_OUT_DIR/schema.log" 2>&1
  PGPASSWORD="$HOST_PSQL_PASSWORD" "$HOST_PSQL_BIN" -h 127.0.0.1 -p "$HOST_PSQL_PORT" -U "$HOST_PSQL_USER" -d "$JOB_DB_NAME" -v ON_ERROR_STOP=1 -f "$rewritten_load_sql" > "$JOB_OUT_DIR/load.log" 2>&1
  PGPASSWORD="$HOST_PSQL_PASSWORD" "$HOST_PSQL_BIN" -h 127.0.0.1 -p "$HOST_PSQL_PORT" -U "$HOST_PSQL_USER" -d "$JOB_DB_NAME" -v ON_ERROR_STOP=1 -f "$JOB_IMPORT_FKINDEX_FILE" > "$JOB_OUT_DIR/fkindexes.log" 2>&1
fi

run_psql_file "$JOB_DB_NAME" "$JOB_WORKSPACE_SCHEMA_SIDECAR_SQL" > "$JOB_OUT_DIR/sidecar-schema.log" 2>&1
run_psql_file "$JOB_DB_NAME" "$JOB_WORKSPACE_SEED_SIDECAR_SQL" -v "hot_modulus=$JOB_TP_HOT_MODULUS" -v "hot_remainder=$JOB_TP_HOT_REMAINDER" > "$JOB_OUT_DIR/sidecar-seed.log" 2>&1

cat > "$JOB_OUT_DIR/prepare-summary.env" <<EOF
job_db_name=$JOB_DB_NAME
job_db_load_policy=$JOB_DB_LOAD_POLICY
job_import_schema_file=$JOB_IMPORT_SCHEMA_FILE
job_import_load_file=$JOB_IMPORT_LOAD_FILE
job_import_fkindex_file=$JOB_IMPORT_FKINDEX_FILE
job_csv_base_dir=$JOB_CSV_BASE_DIR
job_tp_hot_modulus=$JOB_TP_HOT_MODULUS
job_tp_hot_remainder=$JOB_TP_HOT_REMAINDER
EOF
