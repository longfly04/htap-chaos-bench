#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck disable=SC1090
source "$PROJECT_ROOT/config/project-paths.env"
source "${HARNESS_COMMON:-$PROJECT_ROOT/scripts/harness_common.sh}"

QUERY_FILE=""
OUT_FILE=""
DATABASE="${BENCHMARK_DB_NAME:-postgres}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --query-file)
      QUERY_FILE="$2"
      shift 2
      ;;
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
[[ -n "$QUERY_FILE" ]] || fail "--query-file is required"
[[ -n "$OUT_FILE" ]] || fail "--output is required"
mkdir -p "$(dirname "$OUT_FILE")"
QUERY_PATH="$QUERY_FILE"
[[ "$QUERY_PATH" == /* ]] || QUERY_PATH="$LAB_ROOT/$QUERY_PATH"
EXPLAIN_SQL="EXPLAIN (FORMAT JSON) $(tr '\n' ' ' < "$QUERY_PATH")"
run_psql "$DATABASE" "$EXPLAIN_SQL" > "$OUT_FILE"
