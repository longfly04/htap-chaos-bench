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
usage: run_phase5_seed_sweep.sh <base-manifest> <run-prefix> <seed> [seed ...]

Examples:
  bash run_phase5_seed_sweep.sh \
    exp/manifests/phase5/seed-sweep-workload-drift.env \
    paper1-phase5-seed-sweep-workload-drift \
    1 2 3 4 5
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

rewrite_manifest() {
  local src="$1"
  local dst="$2"
  local seed="$3"
  local run_prefix="$4"
  local rq system dataset budget tp_pressure overlap ap_class variant run_id run_name

  manifest_field() {
    local manifest="$1"
    local key="$2"
    local default_value="$3"
    (
      set -a
      export LAB_ROOT="${LAB_ROOT:-$PWD}"
      # shellcheck disable=SC1090
      source "$manifest"
      set +a
      printf '%s' "${!key:-$default_value}"
    )
  }

  rq="$(manifest_field "$src" RQ P5SEEDS)"
  system="$(manifest_field "$src" SYSTEM pg-like)"
  dataset="$(manifest_field "$src" DATASET job)"
  budget="$(manifest_field "$src" BUDGET_TIER budget)"
  tp_pressure="$(manifest_field "$src" TP_PRESSURE tp)"
  overlap="$(manifest_field "$src" OVERLAP overlap)"
  ap_class="$(manifest_field "$src" AP_CLASS ap)"
  variant="$(manifest_field "$src" VARIANT "$(manifest_field "$src" BASELINE native)")"
  run_id="${rq}_${system}_${budget}_${tp_pressure}_${overlap}_${ap_class}_${variant}_s${seed}"
  run_name="${run_prefix}-s${seed}"

  "${PYTHON_BIN:-python}" - "$src" "$dst" "$seed" "$run_id" "$run_name" <<'PY'
import re
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
seed = sys.argv[3]
run_id = sys.argv[4]
run_name = sys.argv[5]
text = src.read_text(encoding='utf-8')

for key, value in {
    'SEED': seed,
    'RUN_ID': run_id,
    'RUN_NAME': run_name,
}.items():
    if not re.search(rf'^{re.escape(key)}=.*$', text, flags=re.M):
        raise SystemExit(f'missing {key} in {src}')
    text = re.sub(rf'^{re.escape(key)}=.*$', f'{key}={value}', text, flags=re.M)

dst.write_text(text, encoding='utf-8')
PY
}

log_status() {
  local status_file="$1"
  local seed="$2"
  local status="$3"
  local run_dir="${4:-}"
  local manifest="${5:-}"
  local log_file="${6:-}"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -Iseconds)" \
    "$seed" \
    "$status" \
    "$run_dir" \
    "$manifest" \
    "$log_file" | tee -a "$status_file"
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

if [[ $# -lt 3 ]]; then
  usage >&2
  exit 1
fi

BASE_MANIFEST="$(resolve_existing_path "$1")" || {
  echo "manifest not found: $1" >&2
  exit 1
}
RUN_PREFIX="$2"
shift 2
SEEDS=("$@")

TMP_MANIFEST_DIR="${TMP_MANIFEST_DIR:-$EXP_ROOT/tmp/phase5-manifests}"
RESULTS_DIR="${PHASE5_RESULTS_DIR:-$EXP_ROOT/results/phase5}"
LOG_DIR="$RESULTS_DIR/seed-sweep-logs"
STATUS_TSV="$RESULTS_DIR/seed-sweep-status.tsv"
RUNLIST="$RESULTS_DIR/seed-sweep-runlist.txt"

mkdir -p "$TMP_MANIFEST_DIR" "$LOG_DIR" "$RESULTS_DIR"
: > "$STATUS_TSV"
: > "$RUNLIST"

completed_runs=0
for seed in "${SEEDS[@]}"; do
  run_label="${RUN_PREFIX}-s${seed}"
  tmp_manifest="$TMP_MANIFEST_DIR/${run_label}.env"
  point_log="$LOG_DIR/${run_label}.log"

  rewrite_manifest "$BASE_MANIFEST" "$tmp_manifest" "$seed" "$RUN_PREFIX"
  log_status "$STATUS_TSV" "$seed" "started" "" "$tmp_manifest" "$point_log"

  if ! LAB_ROOT="$PROJECT_ROOT" PROJECT_ROOT="$PROJECT_ROOT" bash "$RUN_SLICE" "$tmp_manifest" "$run_label" >"$point_log" 2>&1; then
    log_status "$STATUS_TSV" "$seed" "failed" "" "$tmp_manifest" "$point_log"
    continue
  fi

  run_dir="$(resolve_run_dir "$point_log" "$run_label" || true)"
  if [[ -z "$run_dir" || ! -f "$run_dir/summary.json" ]]; then
    log_status "$STATUS_TSV" "$seed" "failed" "$run_dir" "$tmp_manifest" "$point_log"
    continue
  fi

  if ! grep -q '"status": "completed"' "$run_dir/summary.json"; then
    log_status "$STATUS_TSV" "$seed" "failed" "$run_dir" "$tmp_manifest" "$point_log"
    continue
  fi

  printf '%s\n' "$run_dir" >> "$RUNLIST"
  log_status "$STATUS_TSV" "$seed" "completed" "$run_dir" "$tmp_manifest" "$point_log"
  completed_runs=$((completed_runs + 1))
done

printf '%s\n' "$RUNLIST"
printf 'completed %d/%d runs\n' "$completed_runs" "${#SEEDS[@]}" >&2
