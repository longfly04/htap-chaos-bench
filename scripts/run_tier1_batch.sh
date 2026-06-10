#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

PROFILE="${1:-${MEMORY_PROFILE:-4u4g}}"

# shellcheck disable=SC1090
source "$PROJECT_ROOT/scripts/batch_profile_common.sh"
setup_batch_profile "$PROFILE"

LOG_FILE="$PROFILE_LOG_ROOT/tier1-batch.log"
echo "Tier 1 batch ($MEMORY_PROFILE) started at $(date -Iseconds)" | tee "$LOG_FILE"
echo "Using env file: $LAB_ENV_FILE" | tee -a "$LOG_FILE"
echo "Runs root: $RUNS_ROOT" | tee -a "$LOG_FILE"

FIRST_RUN=true
RUN_INDEX=0

run_one() {
  local manifest="$1"
  local label="$2"
  RUN_INDEX=$((RUN_INDEX + 1))
  echo "" | tee -a "$LOG_FILE"
  echo "=== Run $RUN_INDEX/4: $label ===" | tee -a "$LOG_FILE"
  echo "Started at $(date -Iseconds)" | tee -a "$LOG_FILE"

  if $FIRST_RUN; then
    export JOB_DB_LOAD_POLICY=reload
    FIRST_RUN=false
  else
    export JOB_DB_LOAD_POLICY=reuse_if_present
  fi

  local result
  result=$(bash scripts/run_slice.sh "$manifest" "$label" 2>&1 | tail -1)
  echo "Run dir: $result" | tee -a "$LOG_FILE"

  if [[ -f "$result/summary.json" ]]; then
    local status
    status=$(python3 -c "import json; print(json.load(open('$result/summary.json')).get('status','unknown'))" 2>/dev/null || echo unknown)
    echo "Status: $status" | tee -a "$LOG_FILE"
  fi

  [[ -f "$result/run-status.txt" ]] || { echo "Missing run-status.txt for $label" | tee -a "$LOG_FILE"; exit 1; }
  local run_status
  run_status=$(tr -d '\r\n' < "$result/run-status.txt")
  echo "Run status: $run_status" | tee -a "$LOG_FILE"
  [[ "$run_status" == "completed" ]] || { echo "Run did not complete cleanly: $label" | tee -a "$LOG_FILE"; exit 1; }

  "$PROJECT_ROOT/exp/scripts/validation/50_artifact_check.sh" --run-dir "$result" --phase completed
  [[ -s "$result/derived/mixed-baseline.json" ]] || { echo "Missing mixed-baseline.json for $label" | tee -a "$LOG_FILE"; exit 1; }
  [[ -s "$result/derived/workload-sql-set.md" ]] || { echo "Missing workload-sql-set.md for $label" | tee -a "$LOG_FILE"; exit 1; }
  [[ -s "$result/explainability/top-findings.md" ]] || { echo "Missing top-findings.md for $label" | tee -a "$LOG_FILE"; exit 1; }
  echo "Artifact validation passed for $label" | tee -a "$LOG_FILE"
  echo "Finished $label at $(date -Iseconds)" | tee -a "$LOG_FILE"
}

run_one "exp/manifests/tier1-stacking/go-mixed-waitxact-spill-l2.env" "waitxact-spill-l2"
run_one "exp/manifests/tier1-stacking/go-mixed-spill-drift-l2.env" "spill-drift-l2"
run_one "exp/manifests/tier1-stacking/go-mixed-waitxact-deadlock-l2.env" "waitxact-deadlock-l2"
run_one "exp/manifests/tier1-stacking/go-mixed-multifault-l2.env" "multifault-l2"

echo "" | tee -a "$LOG_FILE"
echo "Tier 1 batch completed at $(date -Iseconds)" | tee -a "$LOG_FILE"
