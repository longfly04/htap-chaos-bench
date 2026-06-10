#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck disable=SC1090
source "$PROJECT_ROOT/config/project-paths.env"
export LAB_ROOT="${LAB_ROOT:-$PROJECT_ROOT}"
EXP_ROOT="$PROJECT_ROOT/exp"
RUN_SLICE="${HARNESS_RUN_SLICE:-$PROJECT_ROOT/scripts/run_slice.sh}"

usage() {
  cat <<'EOF'
usage: run_phase5_pair.sh <manifest-a> <manifest-b> <pair-prefix>

Examples:
  bash run_phase5_pair.sh \
    exp/manifests/phase5/head-to-head-workload-drift-go.env \
    exp/manifests/phase5/head-to-head-workload-drift-legacy.env \
    paper1-phase5-head-to-head-workload-drift
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

resolve_run_dir() {
  local log_file="$1"
  local run_label="$2"
  local newest=""
  newest="$(grep -Eo '/[^[:space:]]+/runs/[0-9]{8}-[0-9]{6}-[^[:space:]]+' "$log_file" | tail -n 1 || true)"
  if [[ -n "$newest" && -d "$newest" ]]; then
    printf '%s\n' "$newest"
    return 0
  fi
  newest="$(ls -dt "$PROJECT_ROOT"/runs/*-"$run_label" 2>/dev/null | head -n 1 || true)"
  if [[ -n "$newest" && -d "$newest" ]]; then
    printf '%s\n' "$newest"
    return 0
  fi
  return 1
}

run_one() {
  local manifest="$1"
  local label="$2"
  local log_file="$3"

  if ! LAB_ROOT="$PROJECT_ROOT" PROJECT_ROOT="$PROJECT_ROOT" bash "$RUN_SLICE" "$manifest" "$label" >"$log_file" 2>&1; then
    return 1
  fi

  local run_dir
  run_dir="$(resolve_run_dir "$log_file" "$label" || true)"
  [[ -n "$run_dir" && -f "$run_dir/summary.json" ]] || return 1
  grep -q '"status": "completed"' "$run_dir/summary.json" || return 1
  printf '%s\n' "$run_dir"
}

if [[ $# -ne 3 ]]; then
  usage >&2
  exit 1
fi

MANIFEST_A="$(resolve_existing_path "$1")" || {
  echo "manifest not found: $1" >&2
  exit 1
}
MANIFEST_B="$(resolve_existing_path "$2")" || {
  echo "manifest not found: $2" >&2
  exit 1
}
PAIR_PREFIX="$3"

RESULTS_DIR="${PHASE5_RESULTS_DIR:-$EXP_ROOT/results/phase5}"
LOG_DIR="$RESULTS_DIR/pair-logs"
PAIR_RUNLIST="$RESULTS_DIR/${PAIR_PREFIX}-runlist.txt"
STATUS_TSV="$RESULTS_DIR/${PAIR_PREFIX}-status.tsv"
mkdir -p "$RESULTS_DIR" "$LOG_DIR"
: > "$PAIR_RUNLIST"
: > "$STATUS_TSV"

run_pair_side() {
  local manifest="$1"
  local side="$2"
  local log_file="$LOG_DIR/${PAIR_PREFIX}-${side}.log"
  printf '%s\t%s\tstarted\t%s\t%s\n' "$(date -Iseconds)" "$side" "$manifest" "$log_file" | tee -a "$STATUS_TSV" >&2
  local run_dir
  if ! run_dir="$(run_one "$manifest" "${PAIR_PREFIX}-${side}" "$log_file")"; then
    printf '%s\t%s\tfailed\t%s\t%s\n' "$(date -Iseconds)" "$side" "$manifest" "$log_file" | tee -a "$STATUS_TSV" >&2
    return 1
  fi
  printf '%s\n' "$run_dir" >> "$PAIR_RUNLIST"
  printf '%s\t%s\tcompleted\t%s\t%s\t%s\n' "$(date -Iseconds)" "$side" "$run_dir" "$manifest" "$log_file" | tee -a "$STATUS_TSV" >&2
}

run_pair_side "$MANIFEST_A" side-a
run_pair_side "$MANIFEST_B" side-b
printf '%s\n' "$PAIR_RUNLIST"
