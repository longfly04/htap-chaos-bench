#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

PROFILE="${1:-${MEMORY_PROFILE:-}}"
if [[ -z "$PROFILE" ]]; then
  printf 'usage: %s <4u4g|4u8g|8u8g|8u16g>\n' "$(basename "$0")" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$PROJECT_ROOT/scripts/batch_profile_common.sh"
setup_batch_profile "$PROFILE"
# shellcheck disable=SC1090
source "$PROJECT_ROOT/scripts/harness_common.sh"

LOG_FILE="$PROFILE_LOG_ROOT/matrix.log"
STATUS_FILE="$PROFILE_LOG_ROOT/status.tsv"
RUNLIST_FILE="$PROFILE_LOG_ROOT/runlist.txt"
PREFLIGHT_RUN_DIR="$PROFILE_LOG_ROOT/preflight"

: > "$LOG_FILE"
printf 'step\tstatus\tstarted_at\tfinished_at\n' > "$STATUS_FILE"

record_status() {
  local step="$1"
  local status="$2"
  local started_at="$3"
  local finished_at="$4"
  printf '%s\t%s\t%s\t%s\n' "$step" "$status" "$started_at" "$finished_at" >> "$STATUS_FILE"
}

refresh_runlist() {
  : > "$RUNLIST_FILE"
  shopt -s nullglob
  for path in "$RUNS_ROOT"/*; do
    [[ -d "$path" ]] || continue
    printf '%s\n' "$path" >> "$RUNLIST_FILE"
  done
  shopt -u nullglob
}

run_step() {
  local step="$1"
  shift
  local started_at finished_at
  started_at="$(date -Iseconds)"
  if "$@" 2>&1 | tee -a "$LOG_FILE"; then
    finished_at="$(date -Iseconds)"
    record_status "$step" ok "$started_at" "$finished_at"
  else
    finished_at="$(date -Iseconds)"
    record_status "$step" failed "$started_at" "$finished_at"
    return 1
  fi
}

wait_for_postgres() {
  local container_name="${COMPOSE_PROJECT_NAME}-postgres"
  local attempts="${1:-60}"
  local delay_seconds="${2:-2}"
  local status=""

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_name" 2>/dev/null || true)"
    case "$status" in
      healthy|running)
        printf 'container %s is %s\n' "$container_name" "$status"
        return 0
        ;;
      exited|dead)
        docker logs --tail 80 "$container_name" >&2 || true
        printf 'container %s entered terminal state: %s\n' "$container_name" "$status" >&2
        return 1
        ;;
    esac
    sleep "$delay_seconds"
  done

  docker logs --tail 80 "$container_name" >&2 || true
  printf 'timed out waiting for %s to become ready\n' "$container_name" >&2
  return 1
}

echo "Profile matrix ($MEMORY_PROFILE) started at $(date -Iseconds)" | tee -a "$LOG_FILE"
echo "Using env file: $LAB_ENV_FILE" | tee -a "$LOG_FILE"
echo "Runs root: $RUNS_ROOT" | tee -a "$LOG_FILE"

run_step build-image compose build postgres
run_step start-runtime compose up -d postgres
run_step wait-ready wait_for_postgres
run_step preflight bash exp/scripts/prepare/00_env_sanity.sh --run-dir "$PREFLIGHT_RUN_DIR" --database postgres
run_step tier0 bash scripts/run_tier0_batch.sh "$MEMORY_PROFILE"
refresh_runlist
run_step tier1 bash scripts/run_tier1_batch.sh "$MEMORY_PROFILE"
refresh_runlist
run_step tier2 bash scripts/run_tier2_batch.sh "$MEMORY_PROFILE"
refresh_runlist
run_step tier3 bash scripts/run_tier3_batch.sh "$MEMORY_PROFILE"
refresh_runlist

echo "Profile matrix ($MEMORY_PROFILE) completed at $(date -Iseconds)" | tee -a "$LOG_FILE"
