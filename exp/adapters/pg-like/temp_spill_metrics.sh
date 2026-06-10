#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck disable=SC1090
source "$PROJECT_ROOT/config/project-paths.env"
source "${HARNESS_COMMON:-$PROJECT_ROOT/scripts/harness_common.sh}"

DATABASE="${BENCHMARK_DB_NAME:-postgres}"
OUT_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUT_FILE="$2"
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
[[ -n "$OUT_FILE" ]] || fail "--output is required"
mkdir -p "$(dirname "$OUT_FILE")"
run_psql "$DATABASE" "select datname, temp_files, temp_bytes from pg_stat_database order by datname" > "$OUT_FILE"
