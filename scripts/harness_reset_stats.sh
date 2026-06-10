#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/harness_common.sh"

DATABASE="${BENCHMARK_DB_NAME:-postgres}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --database)
      DATABASE="$2"
      shift 2
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

SQL=$(cat <<'EOF'
DO $$
BEGIN
  PERFORM pg_stat_reset();
  PERFORM pg_stat_reset_shared('bgwriter');
  PERFORM pg_stat_reset_shared('archiver');
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'pg_stat_statements_reset') THEN
    PERFORM pg_stat_statements_reset();
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'pg_stat_kcache_reset') THEN
    PERFORM pg_stat_kcache_reset();
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'pg_qualstats_reset') THEN
    PERFORM pg_qualstats_reset();
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'pg_wait_sampling_reset_profile') THEN
    PERFORM pg_wait_sampling_reset_profile();
  END IF;
END $$;
EOF
)

log "resetting PostgreSQL cumulative stats on database: $DATABASE"
run_psql "$DATABASE" "$SQL" >/dev/null
