#!/usr/bin/env bash
set -euo pipefail

HARNESS_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$HARNESS_SCRIPT_DIR/.." && pwd)"
PROJECT_PATHS_ENV="${PROJECT_PATHS_ENV:-$PROJECT_ROOT/config/project-paths.env}"
if [[ -f "$PROJECT_PATHS_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$PROJECT_PATHS_ENV"
fi
export LAB_ROOT="${LAB_ROOT:-$PWD}"
source "${HARNESS_COMMON:-$HARNESS_SCRIPT_DIR/harness_common.sh}"

usage() {
  cat <<'EOF'
usage: run_slice.sh <manifest.env> [run_name] [--dry-run] [--runs-root PATH]
EOF
}

resolve_existing_path() {
  local candidate="$1"
  if [[ -f "$candidate" ]]; then
    printf '%s\n' "$candidate"
  elif [[ -f "$LAB_ROOT/$candidate" ]]; then
    printf '%s\n' "$LAB_ROOT/$candidate"
  else
    return 1
  fi
}

canonical_run_id() {
  printf '%s_%s_%s_%s_%s_%s_%s_s%s' \
    "${RQ:-RQ0}" \
    "${SYSTEM:-system}" \
    "${BUDGET_TIER:-budget}" \
    "${TP_PRESSURE:-tp}" \
    "${OVERLAP:-overlap}" \
    "${AP_CLASS:-ap}" \
    "${VARIANT:-${BASELINE:-native}}" \
    "${SEED:-0}"
}

DRY_RUN=false
RUNS_ROOT="${RUNS_ROOT:-$LAB_ROOT/runs}"
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --runs-root)
      RUNS_ROOT="$2"
      shift 2
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
[[ $# -ge 1 ]] || { usage >&2; exit 1; }

MANIFEST="$(resolve_existing_path "$1")" || fail "manifest not found: $1"
NAME="${2:-}"
set -a
# shellcheck disable=SC1090
source "$MANIFEST"
set +a

RUN_ID="${RUN_ID:-$(canonical_run_id)}"
RUN_NAME="${RUN_NAME:-$RUN_ID}"
RUN_LABEL="${NAME:-$RUN_NAME}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$RUNS_ROOT/$TIMESTAMP-$RUN_LABEL"
RUNTIME_DIR="$RUN_DIR/runtime"
RUN_STATUS_FILE="$RUN_DIR/run-status.txt"
mkdir -p "$RUNTIME_DIR" "$RUN_DIR/observability" "$RUN_DIR/derived"
cp "$MANIFEST" "$RUN_DIR/manifest.env"
{
  echo "resolved_at=$(date -Iseconds)"
  echo "hostname=$(hostname)"
  echo "run_id=$RUN_ID"
  echo "run_name=$RUN_NAME"
  echo "run_dir=$RUN_DIR"
  echo "runtime_dir=$RUNTIME_DIR"
  echo "lab_root=$LAB_ROOT"
  env | sort | grep -E '^(RQ|RUN_ID|RUN_NAME|SYSTEM|DATASET|VARIANT|OVERLAP|CACHE_MODE|CHAOS_|BENCHMARK_|TP_|AP_|BASELINE|SEED|WORKLOAD_|JOB_|DURATION_|WARMUP_|MEASURE_|LAB_|POSTGRES_|DB_|PLAN_|MEMORY_|REMOTE_|CGROUP_|OBSERVE_|LOCK_|EXPORT_|RESET_|APPLY_SQL_FILE|POST_RUN_HOOK|SCENARIO_FILE|GO_PLATFORM_|DATASET_PACK|ADAPTER|VALIDATION_PROFILE|DRIFT_|HTAP_|PROJECT_)=' || true
} > "$RUN_DIR/manifest.resolved.txt"
: > "$RUN_DIR/stdout.log"
: > "$RUN_DIR/stderr.log"
exec > >(tee -a "$RUN_DIR/stdout.log") 2> >(tee -a "$RUN_DIR/stderr.log" >&2)

STATUS="failed"
DB_CONTAINER_NAME=""
finalize() {
  cat > "$RUN_DIR/summary.json" <<EOF_JSON
{
  "status": "$STATUS",
  "run_id": "$RUN_ID",
  "run_name": "$RUN_NAME",
  "rq": "${RQ:-}",
  "system": "${SYSTEM:-}",
  "dataset": "${DATASET:-}",
  "budget_tier": "${BUDGET_TIER:-}",
  "tp_pressure": "${TP_PRESSURE:-}",
  "ap_class": "${AP_CLASS:-}",
  "overlap": "${OVERLAP:-}",
  "variant": "${VARIANT:-${BASELINE:-}}",
  "seed": "${SEED:-}",
  "cache_mode": "${CACHE_MODE:-}",
  "lab_runtime_mode": "${LAB_RUNTIME_MODE:-container}",
  "memory_profile": "${MEMORY_PROFILE:-}",
  "cgroup_cpu_limit": "${CGROUP_CPU_LIMIT:-}",
  "cgroup_memory_limit": "${CGROUP_MEMORY_LIMIT:-}",
  "cgroup_memory_reservation": "${CGROUP_MEMORY_RESERVATION:-}",
  "lab_env_file": "${LAB_ENV_FILE:-}",
  "compose_project_name": "${COMPOSE_PROJECT_NAME:-}",
  "postgres_image": "${POSTGRES_IMAGE:-}",
  "db_port": "${DB_PORT:-}",
  "required_extensions": "${OBSERVE_REQUIRED_EXTENSIONS:-}",
  "required_preload_libraries": "${OBSERVE_REQUIRED_PRELOAD_LIBRARIES:-}",
  "required_commands": "${OBSERVE_REQUIRED_COMMANDS:-}",
  "pg_activity_enabled": "${OBSERVE_PG_ACTIVITY_ENABLED:-}",
  "manifest": "$MANIFEST",
  "run_dir": "$RUN_DIR",
  "runtime_dir": "$RUNTIME_DIR",
  "db_container_name": "$DB_CONTAINER_NAME"
}
EOF_JSON
}
trap finalize EXIT

log "starting shared run skeleton: $RUN_DIR"
launch_args=()
if $DRY_RUN; then
  launch_args+=(--dry-run)
fi
DB_CONTAINER_NAME="$("${HARNESS_RUNTIME_LAUNCH:-$HARNESS_SCRIPT_DIR/runtime_launch.sh}" "$MANIFEST" "$RUN_DIR" "${launch_args[@]}")"
log "runtime launch result: $DB_CONTAINER_NAME"
finalize

if ! $DRY_RUN && [[ "${RESET_STATS:-false}" == "true" ]]; then
  "${HARNESS_RESET_STATS:-$HARNESS_SCRIPT_DIR/harness_reset_stats.sh}" --database "${BENCHMARK_DB_NAME:-postgres}" || true
fi

if ! $DRY_RUN && [[ -n "${POST_RUN_HOOK:-}" ]]; then
  if [[ "$POST_RUN_HOOK" != /* ]]; then
    POST_RUN_HOOK="$LAB_ROOT/$POST_RUN_HOOK"
  fi
  [[ -x "$POST_RUN_HOOK" ]] || fail "POST_RUN_HOOK is not executable: $POST_RUN_HOOK"
  "$POST_RUN_HOOK" "$RUN_DIR"
fi

if ! $DRY_RUN && [[ "${EXPORT_RUN_ARTIFACTS:-true}" == "true" ]]; then
  "${HARNESS_EXPORT_RUN_ARTIFACTS:-$HARNESS_SCRIPT_DIR/harness_export_run_artifacts.sh}" --run-dir "$RUN_DIR"
fi

if $DRY_RUN; then
  STATUS="dry-run"
elif [[ -f "$RUN_STATUS_FILE" ]]; then
  STATUS="$(tr -d '\r\n' < "$RUN_STATUS_FILE")"
  [[ -n "$STATUS" ]] || STATUS="completed-skeleton"
else
  STATUS="completed-skeleton"
fi
printf '%s\n' "$RUN_DIR"
