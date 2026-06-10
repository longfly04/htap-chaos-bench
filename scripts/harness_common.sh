#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_PATHS_ENV="${PROJECT_PATHS_ENV:-$PROJECT_ROOT/config/project-paths.env}"
if [[ -f "$PROJECT_PATHS_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$PROJECT_PATHS_ENV"
fi

export LAB_ROOT="${LAB_ROOT:-${PWD}}"
if [[ -d "$PROJECT_ROOT/pglab" ]]; then
  PGLAB_ROOT="${PGLAB_ROOT:-$PROJECT_ROOT/pglab}"
else
  PGLAB_ROOT="${PGLAB_ROOT:-$LAB_ROOT/pglab}"
fi
ENV_FILE=""
COMPOSE_FILE="${COMPOSE_FILE:-$PGLAB_ROOT/compose/docker-compose.yml}"

is_source_runtime() {
  [[ "${LAB_RUNTIME_MODE:-container}" == "source" ]]
}

source_pg_bin_dir() {
  if [[ -n "${SOURCE_PG_BINDIR:-}" ]]; then
    printf '%s' "$SOURCE_PG_BINDIR"
    return
  fi
  if [[ -n "${PGROOT:-}" ]]; then
    printf '%s' "$PGROOT/bin"
    return
  fi
  if command -v pg_config >/dev/null 2>&1; then
    pg_config --bindir
    return
  fi
  if command -v psql >/dev/null 2>&1; then
    dirname "$(command -v psql)"
    return
  fi
  fail "SOURCE_PG_BINDIR or PGROOT is required for source runtime"
}

source_pg_host() {
  printf '%s' "${SOURCE_PG_HOST:-127.0.0.1}"
}

source_pg_port() {
  printf '%s' "${SOURCE_PG_PORT:-56437}"
}

source_pg_config() {
  local bindir
  bindir="$(source_pg_bin_dir)"
  if [[ -x "$bindir/pg_config" ]]; then
    printf '%s' "$bindir/pg_config"
    return
  fi
  if command -v pg_config >/dev/null 2>&1; then
    command -v pg_config
    return
  fi
  fail "pg_config is required for source runtime"
}

benchmark_pg_host() {
  if is_source_runtime; then
    source_pg_host
    return
  fi
  ensure_env_file
  printf '%s' "${DB_HOST:-127.0.0.1}"
}

benchmark_pg_port() {
  if is_source_runtime; then
    source_pg_port
    return
  fi
  ensure_env_file
  printf '%s' "${DB_PORT:-5432}"
}

sysbench_bin() {
  if [[ -n "${SYSBENCH_BIN:-}" ]]; then
    printf '%s' "$SYSBENCH_BIN"
    return
  fi
  if command -v sysbench >/dev/null 2>&1; then
    command -v sysbench
    return
  fi
  fail "SYSBENCH_BIN or sysbench in PATH is required"
}

source_pg_user() {
  printf '%s' "${SOURCE_PG_USER:-${DB_SUPERUSER:-postgres}}"
}

workspace_to_host_path() {
  local path="$1"
  if [[ -n "${PROJECT_WORKSPACE_ROOT:-}" && "$path" == "$PROJECT_WORKSPACE_ROOT"* ]]; then
    printf '%s/%s' "$PROJECT_ROOT" "${path#"$PROJECT_WORKSPACE_ROOT"/}"
  elif [[ "$path" == /workspace/sql/* ]]; then
    printf '%s/exp/sql/%s' "$PROJECT_ROOT" "${path#/workspace/sql/}"
  elif [[ "$path" == /workspace/* ]]; then
    printf '%s/%s' "$LAB_ROOT" "${path#/workspace/}"
  else
    printf '%s' "$path"
  fi
}

host_to_workspace_path() {
  local path="$1"
  if [[ -n "${PROJECT_ROOT:-}" && -n "${PROJECT_WORKSPACE_ROOT:-}" && "$path" == "$PROJECT_ROOT"* ]]; then
    if [[ "$path" == "$PROJECT_ROOT" ]]; then
      printf '%s' "$PROJECT_WORKSPACE_ROOT"
    else
      printf '%s/%s' "$PROJECT_WORKSPACE_ROOT" "${path#"$PROJECT_ROOT"/}"
    fi
  elif [[ "$path" == "$LAB_ROOT"* ]]; then
    if [[ "$path" == "$LAB_ROOT" ]]; then
      printf '/workspace'
    else
      printf '/workspace/%s' "${path#"$LAB_ROOT"/}"
    fi
  else
    printf '%s' "$path"
  fi
}

run_pg_activity_capture() {
  ensure_env_file
  local output_path="$1"
  local timeout_seconds="${2:-${OBSERVE_PG_ACTIVITY_TIMEOUT_SECONDS:-3}}"
  local database="${3:-${BENCHMARK_DB_NAME:-postgres}}"
  local pg_user="${4:-${DB_SUPERUSER:-postgres}}"
  local pg_password="${5:-${DB_SUPERUSER_PASSWORD:-postgres}}"
  local runtime_output_path="$output_path"

  [[ -n "$output_path" ]] || fail "pg_activity output path is required"
  [[ "$timeout_seconds" =~ ^[0-9]+$ ]] || fail "pg_activity timeout must be an integer"

  if is_source_runtime; then
    OUTPUT_PATH="$runtime_output_path" \
    PG_ACTIVITY_TIMEOUT_SECONDS="$timeout_seconds" \
    PGHOST="$(source_pg_host)" \
    PGPORT="$(source_pg_port)" \
    PGUSER="$pg_user" \
    PGDATABASE="$database" \
    PGPASSWORD="$pg_password" \
    "${PYTHON_BIN:-python}" - <<'PY'
import os
import pathlib
import shutil
import signal
import subprocess
import time

output_path = pathlib.Path(os.environ["OUTPUT_PATH"])
timeout_seconds = max(int(os.environ.get("PG_ACTIVITY_TIMEOUT_SECONDS", "3") or "3"), 1)
output_path.parent.mkdir(parents=True, exist_ok=True)
tmp_path = output_path.with_name(output_path.name + ".tmp")
stderr_path = output_path.with_name(output_path.name + ".stderr.txt")
for path in (output_path, tmp_path, stderr_path):
    try:
        path.unlink()
    except FileNotFoundError:
        pass
cmd = shutil.which("pg_activity")
if not cmd:
    raise SystemExit(127)
proc = subprocess.Popen([cmd, "--output", str(tmp_path)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
try:
    time.sleep(timeout_seconds)
    if proc.poll() is None:
        proc.send_signal(signal.SIGINT)
    try:
        returncode = proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        returncode = proc.wait(timeout=5)
finally:
    stderr_text = proc.stderr.read() if proc.stderr is not None else ""
if stderr_text.strip():
    stderr_path.write_text(stderr_text, encoding="utf-8")
if tmp_path.exists() and tmp_path.stat().st_size > 0:
    output_path.write_bytes(tmp_path.read_bytes())
    tmp_path.unlink()
if output_path.exists() and output_path.stat().st_size > 0:
    raise SystemExit(0)
raise SystemExit(returncode if returncode else 1)
PY
    return
  fi

  runtime_output_path="$(host_to_workspace_path "$output_path")"
  compose exec -T \
    -e OUTPUT_PATH="$runtime_output_path" \
    -e PG_ACTIVITY_TIMEOUT_SECONDS="$timeout_seconds" \
    -e PGHOST=127.0.0.1 \
    -e PGPORT=5432 \
    -e PGUSER="$pg_user" \
    -e PGDATABASE="$database" \
    -e PGPASSWORD="$pg_password" \
    "${DB_SERVICE_NAME:-postgres}" \
    python3 - <<'PY'
import os
import pathlib
import shutil
import signal
import subprocess
import time

output_path = pathlib.Path(os.environ["OUTPUT_PATH"])
timeout_seconds = max(int(os.environ.get("PG_ACTIVITY_TIMEOUT_SECONDS", "3") or "3"), 1)
output_path.parent.mkdir(parents=True, exist_ok=True)
tmp_path = output_path.with_name(output_path.name + ".tmp")
stderr_path = output_path.with_name(output_path.name + ".stderr.txt")
for path in (output_path, tmp_path, stderr_path):
    try:
        path.unlink()
    except FileNotFoundError:
        pass
cmd = shutil.which("pg_activity")
if not cmd:
    raise SystemExit(127)
proc = subprocess.Popen([cmd, "--output", str(tmp_path)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
try:
    time.sleep(timeout_seconds)
    if proc.poll() is None:
        proc.send_signal(signal.SIGINT)
    try:
        returncode = proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        returncode = proc.wait(timeout=5)
finally:
    stderr_text = proc.stderr.read() if proc.stderr is not None else ""
if stderr_text.strip():
    stderr_path.write_text(stderr_text, encoding="utf-8")
if tmp_path.exists() and tmp_path.stat().st_size > 0:
    output_path.write_bytes(tmp_path.read_bytes())
    tmp_path.unlink()
if output_path.exists() and output_path.stat().st_size > 0:
    raise SystemExit(0)
raise SystemExit(returncode if returncode else 1)
PY
}

pg_activity_capture_timeout() {
  local timeout_seconds="${1:-${OBSERVE_PG_ACTIVITY_TIMEOUT_SECONDS:-3}}"
  local refresh_seconds="${2:-${OBSERVE_PG_ACTIVITY_REFRESH_SECONDS:-1}}"

  [[ "$timeout_seconds" =~ ^[0-9]+$ ]] || fail "pg_activity timeout must be an integer"
  [[ "$refresh_seconds" =~ ^[0-9]+$ ]] || fail "pg_activity refresh interval must be an integer"
  if (( timeout_seconds <= refresh_seconds )); then
    timeout_seconds=$((refresh_seconds + 1))
  fi
  printf '%s' "$timeout_seconds"
}

pg_activity_csv_row_count() {
  local output_path="$1"
  ${PYTHON_BIN:-python} - "$output_path" <<'PY'
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
}

append_pg_activity_manifest_entry() {
  local manifest_file="$1"
  local sample_index="$2"
  local ts_epoch_ms="$3"
  local elapsed_seconds="$4"
  local phase="$5"
  local status="$6"
  local row_count="$7"
  local output_file="$8"
  local stderr_file="$9"
  local exit_code="${10}"

  ${PYTHON_BIN:-python} - "$manifest_file" "$sample_index" "$ts_epoch_ms" "$elapsed_seconds" "$phase" "$status" "$row_count" "$output_file" "$stderr_file" "$exit_code" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
entry = {
    "sample_index": int(sys.argv[2]),
    "ts_epoch_ms": int(sys.argv[3]),
    "elapsed_seconds": float(sys.argv[4]),
    "phase": sys.argv[5],
    "status": sys.argv[6],
    "row_count": int(sys.argv[7]),
    "output_file": sys.argv[8],
    "stderr_file": sys.argv[9],
    "exit_code": int(sys.argv[10]),
}
with manifest_path.open("a", encoding="utf-8") as fh:
    fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
PY
}

capture_pg_activity_timeline_snapshot() {
  local run_dir="$1"
  local sample_index="$2"
  local ts_epoch_ms="$3"
  local elapsed_seconds="$4"
  local phase="$5"
  local sample_label="${6:-}"
  local database="${7:-${BENCHMARK_DB_NAME:-postgres}}"
  local pg_user="${8:-${DB_SUPERUSER:-postgres}}"
  local pg_password="${9:-${DB_SUPERUSER_PASSWORD:-postgres}}"
  local timeline_dir="$run_dir/observability/timeline"
  local pg_activity_dir="$timeline_dir/pg-activity"
  local manifest_file="$timeline_dir/pg-activity-snapshots.jsonl"
  local capture_timeout phase_tag sample_tag snapshot_file stderr_file status row_count exit_code

  if [[ "${OBSERVE_PG_ACTIVITY_ENABLED:-false}" != "true" ]]; then
    return 0
  fi

  mkdir -p "$timeline_dir" "$pg_activity_dir"
  capture_timeout="$(pg_activity_capture_timeout "${OBSERVE_PG_ACTIVITY_TIMEOUT_SECONDS:-3}" "${OBSERVE_PG_ACTIVITY_REFRESH_SECONDS:-1}")"
  phase_tag="$(printf '%s' "$phase" | tr -c '[:alnum:]' '-')"
  if [[ -n "$sample_label" ]]; then
    sample_tag="$(printf '%s' "$sample_label" | tr -c '[:alnum:]' '-')"
  else
    sample_tag="sample-$(printf '%05d' "$sample_index")"
  fi
  snapshot_file="$pg_activity_dir/${sample_tag}-${phase_tag}.csv"
  stderr_file="${snapshot_file}.stderr.txt"
  status="captured"
  row_count="0"
  exit_code="0"

  set +e
  run_pg_activity_capture "$snapshot_file" "$capture_timeout" "$database" "$pg_user" "$pg_password"
  exit_code=$?
  set -e

  if [[ -f "$snapshot_file" ]]; then
    row_count="$(pg_activity_csv_row_count "$snapshot_file")"
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

  append_pg_activity_manifest_entry "$manifest_file" "$sample_index" "$ts_epoch_ms" "$elapsed_seconds" "$phase" "$status" "$row_count" "$snapshot_file" "$stderr_file" "$exit_code"
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

ensure_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

ensure_env_file() {
  local env_file="${LAB_ENV_FILE:-$PGLAB_ROOT/compose/.env}"
  if [[ "$env_file" != /* ]]; then
    env_file="$LAB_ROOT/$env_file"
  fi
  ENV_FILE="$env_file"
  [[ -f "$ENV_FILE" ]] || fail "env file not found: $ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
}

compose() {
  local compose_file="$COMPOSE_FILE"
  [[ "$compose_file" == /* ]] || compose_file="$LAB_ROOT/$compose_file"
  ensure_env_file
  if docker compose version >/dev/null 2>&1; then
    docker compose --env-file "$ENV_FILE" -f "$compose_file" "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose --env-file "$ENV_FILE" -f "$compose_file" "$@"
  else
    fail "docker compose plugin or docker-compose is required"
  fi
}

wait_for_db() {
  ensure_env_file
  local retries="${1:-60}"
  local sleep_seconds="${2:-5}"
  local i
  local db_service_name="${DB_SERVICE_NAME:-postgres}"
  if is_source_runtime; then
    local pg_isready_bin
    pg_isready_bin="$(source_pg_bin_dir)/pg_isready"
    for ((i = 1; i <= retries; i++)); do
      if "$pg_isready_bin" -h "$(source_pg_host)" -p "$(source_pg_port)" -U "$(source_pg_user)" -d postgres >/dev/null 2>&1; then
        log "PostgreSQL is ready"
        return 0
      fi
      log "waiting for PostgreSQL ($i/$retries)"
      sleep "$sleep_seconds"
    done
    fail "PostgreSQL did not become ready in time"
  fi
  for ((i = 1; i <= retries; i++)); do
    if compose exec -T -e PGPASSWORD="${DB_SUPERUSER_PASSWORD:-postgres}" "$db_service_name" psql -h 127.0.0.1 -U "${DB_SUPERUSER:-postgres}" -d postgres -Atqc "select 1" >/dev/null 2>&1; then
      log "PostgreSQL is ready"
      return 0
    fi
    log "waiting for PostgreSQL ($i/$retries)"
    sleep "$sleep_seconds"
  done
  fail "PostgreSQL did not become ready in time"
}

run_psql() {
  ensure_env_file
  local database="$1"
  local sql="$2"
  if is_source_runtime; then
    local psql_bin
    psql_bin="$(source_pg_bin_dir)/psql"
    PGPASSWORD="${DB_SUPERUSER_PASSWORD:-postgres}" "$psql_bin" -h "$(source_pg_host)" -p "$(source_pg_port)" -U "$(source_pg_user)" -d "$database" -v ON_ERROR_STOP=1 -Atqc "$sql"
    return
  fi
  compose exec -T -e PGPASSWORD="${DB_SUPERUSER_PASSWORD:-postgres}" "${DB_SERVICE_NAME:-postgres}" psql -h 127.0.0.1 -U "${DB_SUPERUSER:-postgres}" -d "$database" -v ON_ERROR_STOP=1 -Atqc "$sql"
}

run_psql_file() {
  ensure_env_file
  local database="$1"
  local file_path="$2"
  shift 2
  local psql_args=("$@")
  if is_source_runtime; then
    local psql_bin
    local host_path
    psql_bin="$(source_pg_bin_dir)/psql"
    host_path="$(workspace_to_host_path "$file_path")"
    PGPASSWORD="${DB_SUPERUSER_PASSWORD:-postgres}" "$psql_bin" -h "$(source_pg_host)" -p "$(source_pg_port)" -U "$(source_pg_user)" -d "$database" -v ON_ERROR_STOP=1 "${psql_args[@]}" -f "$host_path"
    return
  fi
  compose exec -T -e PGPASSWORD="${DB_SUPERUSER_PASSWORD:-postgres}" "${DB_SERVICE_NAME:-postgres}" psql -h 127.0.0.1 -U "${DB_SUPERUSER:-postgres}" -d "$database" -v ON_ERROR_STOP=1 "${psql_args[@]}" -f "$file_path"
}
