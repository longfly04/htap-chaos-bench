#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
EXP_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUN_DIR=""
ADAPTER_ROOT="${ADAPTER_ROOT:-$EXP_ROOT/adapters/pg-like}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)
      RUN_DIR="$2"
      shift 2
      ;;
    --adapter-root)
      ADAPTER_ROOT="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done
[[ -n "$RUN_DIR" ]] || { echo "--run-dir is required" >&2; exit 1; }
mkdir -p "$RUN_DIR/validation"

profile_present=false
[[ -f "$ADAPTER_ROOT/profile.env" ]] && profile_present=true
plan_capture_present=false
[[ -x "$ADAPTER_ROOT/plan_capture.sh" || -f "$ADAPTER_ROOT/plan_capture.sh" ]] && plan_capture_present=true
temp_spill_present=false
[[ -x "$ADAPTER_ROOT/temp_spill_metrics.sh" || -f "$ADAPTER_ROOT/temp_spill_metrics.sh" ]] && temp_spill_present=true
capabilities_present=false
[[ -x "$ADAPTER_ROOT/capabilities.sh" || -f "$ADAPTER_ROOT/capabilities.sh" ]] && capabilities_present=true
adapter_id=""
plan_capture_mode=""
lock_observation=""
temp_spill_metrics=""
shared_memory_control=""
session_memory_control=""
plan_capture_format=""
if $capabilities_present; then
  while IFS='=' read -r key value; do
    case "$key" in
      ADAPTER_ID) adapter_id="$value" ;;
      PLAN_CAPTURE) plan_capture_mode="$value" ;;
      LOCK_OBSERVATION) lock_observation="$value" ;;
      TEMP_SPILL_METRICS) temp_spill_metrics="$value" ;;
      SHARED_MEMORY_CONTROL) shared_memory_control="$value" ;;
      SESSION_MEMORY_CONTROL) session_memory_control="$value" ;;
      PLAN_CAPTURE_FORMAT) plan_capture_format="$value" ;;
    esac
  done < <(bash "$ADAPTER_ROOT/capabilities.sh")
fi

cat > "$RUN_DIR/validation/adapter-check.json" <<EOF
{
  "adapter_root": "$ADAPTER_ROOT",
  "profile_present": $profile_present,
  "plan_capture_present": $plan_capture_present,
  "temp_spill_metrics_present": $temp_spill_present,
  "capabilities_present": $capabilities_present,
  "adapter_id": "$adapter_id",
  "plan_capture": "$plan_capture_mode",
  "lock_observation": "$lock_observation",
  "temp_spill_metrics": "$temp_spill_metrics",
  "shared_memory_control": "$shared_memory_control",
  "session_memory_control": "$session_memory_control",
  "plan_capture_format": "$plan_capture_format"
}
EOF
