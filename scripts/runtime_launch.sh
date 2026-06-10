#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_PATHS_ENV="${PROJECT_PATHS_ENV:-$PROJECT_ROOT/config/project-paths.env}"
if [[ -f "$PROJECT_PATHS_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$PROJECT_PATHS_ENV"
fi

usage() {
  cat <<'EOF'
usage: runtime_launch.sh <manifest.env> <run_dir> [--dry-run]
EOF
}

DRY_RUN=false
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done
set -- "${POSITIONAL[@]}"
[[ $# -ge 2 ]] || { usage >&2; exit 1; }

MANIFEST="$1"
RUN_DIR="$2"
[[ -f "$MANIFEST" ]] || { echo "manifest not found: $MANIFEST" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$MANIFEST"
set +a

export LAB_ROOT="${LAB_ROOT:-$PWD}"
LAB_ENV_FILE="${LAB_ENV_FILE:-$LAB_ROOT/pglab/compose/.env}"
if [[ "$LAB_ENV_FILE" != /* ]]; then
  LAB_ENV_FILE="$LAB_ROOT/$LAB_ENV_FILE"
fi
LAB_RUNTIME_MODE="${LAB_RUNTIME_MODE:-container}"
APPLY_SQL_FILE="${APPLY_SQL_FILE:-}"
BENCHMARK_DB_NAME="${BENCHMARK_DB_NAME:-${DB_NAME:-benchdb}}"
DB_SERVICE_NAME="${DB_SERVICE_NAME:-postgres}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-$(basename "$LAB_ROOT" | tr -cs 'A-Za-z0-9' '-')}"
DB_CONTAINER_NAME="${DB_CONTAINER_NAME:-${COMPOSE_PROJECT_NAME}-${DB_SERVICE_NAME}}"

mkdir -p "$RUN_DIR/runtime"
{
  echo "started_at=$(date -Iseconds)"
  echo "lab_root=$LAB_ROOT"
  echo "lab_env_file=$LAB_ENV_FILE"
  echo "compose_project_name=$COMPOSE_PROJECT_NAME"
  echo "db_service_name=$DB_SERVICE_NAME"
  echo "db_container_name=$DB_CONTAINER_NAME"
  echo "benchmark_db_name=$BENCHMARK_DB_NAME"
  echo "runtime_mode=$LAB_RUNTIME_MODE"
  echo "apply_sql_file=$APPLY_SQL_FILE"
} > "$RUN_DIR/runtime/runtime.env"

if $DRY_RUN; then
  echo "dry-run"
  exit 0
fi

start_args=(--database "$BENCHMARK_DB_NAME")
if [[ -n "$APPLY_SQL_FILE" ]]; then
  start_args+=(--apply-sql "$APPLY_SQL_FILE")
fi
"${HARNESS_START:-$SCRIPT_DIR/harness_start.sh}" "${start_args[@]}" > "$RUN_DIR/runtime/start.log" 2>&1
printf '%s\n' "$DB_CONTAINER_NAME"
