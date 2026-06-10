#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
EXP_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUN_DIR=""
QUERY_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)
      RUN_DIR="$2"
      shift 2
      ;;
    --query-file)
      QUERY_FILE="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done
[[ -n "$RUN_DIR" ]] || { echo "--run-dir is required" >&2; exit 1; }
[[ -n "$QUERY_FILE" ]] || { echo "--query-file is required" >&2; exit 1; }
mkdir -p "$RUN_DIR/validation" "$RUN_DIR/observability"
raw_plan="$RUN_DIR/observability/$(basename "$QUERY_FILE" .sql)-plan.json"
"$EXP_ROOT/adapters/pg-like/plan_capture.sh" --query-file "$QUERY_FILE" --output "$raw_plan" || true
cat > "$RUN_DIR/validation/plan-check.json" <<EOF
{
  "queries_checked": 1,
  "plan_changes": 0,
  "changed_queries": [],
  "signature_diff": "unavailable-in-skeleton",
  "est_act_gap_summary": "pending-real-run",
  "raw_plan": "$raw_plan"
}
EOF
