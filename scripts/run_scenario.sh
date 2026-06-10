#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXP_ROOT="$PROJECT_ROOT/exp"
# shellcheck disable=SC1090
source "$PROJECT_ROOT/config/project-paths.env"
source "${HARNESS_COMMON:-$PROJECT_ROOT/scripts/harness_common.sh}"
# shellcheck disable=SC1090
source "$EXP_ROOT/scripts/job_config.sh"
job_load_runtime_config "$EXP_ROOT"

RUN_DIR="${1:-}"
[[ -n "$RUN_DIR" ]] || fail "run directory is required"

resolve_lab_path() {
  local path="$1"
  if [[ "$path" == /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$LAB_ROOT" "$path"
  fi
}

workspace_run_dir() {
  case "$RUN_DIR" in
    "$LAB_ROOT"/runs/*)
      printf '%s/%s\n' "${LAB_WORKSPACE_RUN_ROOT:?missing LAB_WORKSPACE_RUN_ROOT}" "${RUN_DIR#"$LAB_ROOT"/runs/}"
      ;;
    *)
      fail "run directory is not under LAB_ROOT/runs: $RUN_DIR"
      ;;
  esac
}

GO_BIN="$(resolve_lab_path "${GO_PLATFORM_BIN:-$PROJECT_ROOT/bin/htap-chaos-bench}")"
SCENARIO_PATH="$(resolve_lab_path "${SCENARIO_FILE:-}")"
DATASET_PACK_PATH="$(resolve_lab_path "${DATASET_PACK:-}")"
MANIFEST_PATH="$RUN_DIR/manifest.env"
TP_PROFILE_ENV="$RUN_DIR/derived/tp-profile.env"
TP_SQL_WORKSPACE_PATH="$(workspace_run_dir)/derived/tp-template-resolved.sql"
FRESHNESS_SQL_WORKSPACE_PATH="$(workspace_run_dir)/derived/freshness-probe.sql"
SYNC_LATENCY_SQL_WORKSPACE_PATH="$(workspace_run_dir)/derived/sync-latency-probe.sql"
WORKLOAD_DRIFT_QUERY_HOST_PATH="$RUN_DIR/derived/query-drift-sample.sql"
EXP_ROOT="$PROJECT_ROOT/exp"
TP_BASELINE_SCRIPT="$EXP_ROOT/scripts/run/run_tp_baseline.sh"
MIXED_BASELINE_SCRIPT="$EXP_ROOT/scripts/run/run_mixed_baseline.sh"

[[ -x "$GO_BIN" ]] || fail "Go platform binary is not executable: $GO_BIN"
[[ -f "$SCENARIO_PATH" ]] || fail "scenario file not found: $SCENARIO_PATH"
[[ -d "$DATASET_PACK_PATH" ]] || fail "dataset pack not found: $DATASET_PACK_PATH"
[[ -f "$MANIFEST_PATH" ]] || fail "manifest file not found: $MANIFEST_PATH"
[[ -x "$TP_BASELINE_SCRIPT" ]] || fail "TP baseline script is not executable: $TP_BASELINE_SCRIPT"
[[ -x "$MIXED_BASELINE_SCRIPT" ]] || fail "mixed baseline script is not executable: $MIXED_BASELINE_SCRIPT"

"$GO_BIN" materialize-tp \
  --manifest "$MANIFEST_PATH" \
  --scenario "$SCENARIO_PATH" \
  --dataset-pack "$DATASET_PACK_PATH" \
  --run-dir "$RUN_DIR"

[[ -f "$TP_PROFILE_ENV" ]] || fail "generated TP profile env not found: $TP_PROFILE_ENV"
set -a
# shellcheck disable=SC1090
source "$TP_PROFILE_ENV"
set +a
export JOB_TP_SQL_FILE="$TP_SQL_WORKSPACE_PATH"
if [[ -f "$RUN_DIR/derived/freshness-probe.sql" ]]; then
  export JOB_FRESHNESS_PROBE_SQL_FILE="$FRESHNESS_SQL_WORKSPACE_PATH"
fi
if [[ -f "$RUN_DIR/derived/sync-latency-probe.sql" ]]; then
  export JOB_SYNC_LATENCY_PROBE_SQL_FILE="$SYNC_LATENCY_SQL_WORKSPACE_PATH"
fi
if [[ -f "$RUN_DIR/derived/query-drift-sample.sql" ]]; then
  export JOB_WORKLOAD_DRIFT_QUERY_FILE="$WORKLOAD_DRIFT_QUERY_HOST_PATH"
fi

if [[ -n "${AP_CLASS:-}" && "${AP_CLASS:-na}" != "na" ]]; then
  "$MIXED_BASELINE_SCRIPT" "$RUN_DIR"
else
  "$TP_BASELINE_SCRIPT" "$RUN_DIR"
fi
