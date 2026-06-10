#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/harness_common.sh"

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
ensure_env_file
mkdir -p "$RUN_DIR/compose" "$RUN_DIR/configs" "$RUN_DIR/observability"
cp "$ENV_FILE" "$RUN_DIR/configs/pglab.env"
[[ -f "$COMPOSE_FILE" ]] && cp "$COMPOSE_FILE" "$RUN_DIR/compose/docker-compose.yml" || true
compose ps > "$RUN_DIR/compose/compose-ps.txt" || true
compose logs --no-color --tail 200 "${DB_SERVICE_NAME:-postgres}" > "$RUN_DIR/compose/postgres.log" || true

if [[ "${EXPORT_PG_STATS:-true}" == "true" ]]; then
  "${HARNESS_EXPORT_PG_STATS:-$SCRIPT_DIR/harness_export_pg_stats.sh}" --run-dir "$RUN_DIR" --database "${BENCHMARK_DB_NAME:-postgres}" || true
fi

if [[ "${LOCK_OBSERVE_MODE:-off}" != "off" ]]; then
  "${HARNESS_OBSERVE_LOCKS:-$SCRIPT_DIR/harness_observe_locks.sh}" --run-dir "$RUN_DIR" --database "${BENCHMARK_DB_NAME:-postgres}" || true
fi
