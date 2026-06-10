#!/usr/bin/env bash
set -euo pipefail

RUN_DIR=""
PHASE="in-run"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)
      RUN_DIR="$2"
      shift 2
      ;;
    --phase)
      PHASE="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done
[[ -n "$RUN_DIR" ]] || { echo "--run-dir is required" >&2; exit 1; }
case "$PHASE" in
  in-run|completed)
    ;;
  *)
    echo "unsupported phase: $PHASE" >&2
    exit 1
    ;;
esac
mkdir -p "$RUN_DIR/validation"

missing=()
optional_missing=()
status_issues=()

require_path() {
  local path="$1"
  [[ -e "$path" ]] || missing+=("$path")
}

require_non_empty_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    missing+=("$path")
    return
  fi
  [[ -s "$path" ]] || missing+=("$path (empty)")
}

optional_path() {
  local path="$1"
  [[ -e "$path" ]] || optional_missing+=("$path")
}

require_path "$RUN_DIR/manifest.env"
require_path "$RUN_DIR/manifest.resolved.txt"
require_non_empty_file "$RUN_DIR/stdout.log"
require_path "$RUN_DIR/stderr.log"
require_path "$RUN_DIR/summary.json"
require_path "$RUN_DIR/runtime/runtime.env"
require_path "$RUN_DIR/configs/pglab.env"
require_path "$RUN_DIR/compose/compose-ps.txt"
require_path "$RUN_DIR/derived"
require_path "$RUN_DIR/validation"
require_path "$RUN_DIR/observability"
require_path "$RUN_DIR/tp"
require_path "$RUN_DIR/ap"
require_path "$RUN_DIR/htapcheck"
require_path "$RUN_DIR/figures"
require_path "$RUN_DIR/explainability"
require_non_empty_file "$RUN_DIR/derived/tp-profile.env"
require_non_empty_file "$RUN_DIR/derived/tp-profile.json"
require_non_empty_file "$RUN_DIR/derived/tp-template-resolved.sql"
if [[ "$PHASE" == "completed" ]]; then
  require_non_empty_file "$RUN_DIR/explainability/top-findings.md"
fi

if [[ -f "$RUN_DIR/derived/mixed-baseline.json" ]]; then
  require_non_empty_file "$RUN_DIR/derived/mixed-baseline.json"
fi
if [[ -f "$RUN_DIR/derived/tp-baseline.json" ]]; then
  require_non_empty_file "$RUN_DIR/derived/tp-baseline.json"
fi
if [[ -f "$RUN_DIR/derived/ap-baseline.json" ]]; then
  require_non_empty_file "$RUN_DIR/derived/ap-baseline.json"
fi

report_manifest="$RUN_DIR/report/report-manifest.json"
report_bundle_status="absent"
report_bundle_missing_json='[]'
if [[ -f "$report_manifest" ]]; then
  mapfile -t report_bundle_lines < <("${PYTHON_BIN:-python}" - "$report_manifest" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    manifest = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    print("malformed")
    print(json.dumps(["report/report-manifest.json"]))
    raise SystemExit(0)
print(manifest.get("status", "unknown"))
print(json.dumps(manifest.get("missing_required_artifacts", []) or []))
PY
)
  report_bundle_status="${report_bundle_lines[0]:-unknown}"
  report_bundle_missing_json="${report_bundle_lines[1]:-[]}"
  mapfile -t report_bundle_missing < <("${PYTHON_BIN:-python}" -c 'import json,sys; data=json.loads(sys.stdin.read()); print("\n".join(data))' <<<"$report_bundle_missing_json")
  for path in "${report_bundle_missing[@]:-}"; do
    [[ -n "$path" ]] && missing+=("$path")
  done
fi

if [[ -f "$RUN_DIR/derived/freshness-profile.json" ]]; then
  require_non_empty_file "$RUN_DIR/derived/freshness-check.json"
  require_non_empty_file "$RUN_DIR/htapcheck/freshness.csv"
fi

if [[ -f "$RUN_DIR/derived/sync-latency-profile.json" ]]; then
  require_non_empty_file "$RUN_DIR/derived/sync-latency.json"
  require_non_empty_file "$RUN_DIR/htapcheck/sync-latency.csv"
fi

if [[ -f "$RUN_DIR/derived/workload-drift-profile.json" || -f "$RUN_DIR/derived/query-drift-sample.sql" ]]; then
  require_non_empty_file "$RUN_DIR/derived/query-drift-sample.sql"
fi

if [[ -f "$RUN_DIR/derived/chaos-profile.json" ]]; then
  require_path "$RUN_DIR/derived/cleanup-report.json"
  require_path "$RUN_DIR/derived/target-selector.resolved.json"
  if [[ -f "$RUN_DIR/derived/waitxact-chaos.json" ]]; then
    require_non_empty_file "$RUN_DIR/derived/waitxact-chaos.json"
  fi
  if [[ -f "$RUN_DIR/derived/deadlock-pair-chaos.json" ]]; then
    require_non_empty_file "$RUN_DIR/derived/deadlock-pair-chaos.json"
  fi
  if [[ -f "$RUN_DIR/derived/spill-pressure-chaos.json" ]]; then
    require_non_empty_file "$RUN_DIR/derived/spill-pressure-chaos.json"
  fi
fi

if [[ "$PHASE" == "completed" ]]; then
  if [[ -f "$RUN_DIR/run-status.txt" ]]; then
    run_status="$(tr -d '\r\n' < "$RUN_DIR/run-status.txt")"
    [[ "$run_status" == "completed" ]] || status_issues+=("run-status.txt=$run_status")
  else
    status_issues+=("run-status.txt missing")
  fi

  if [[ -f "$RUN_DIR/summary.json" ]]; then
    summary_status="$("${PYTHON_BIN:-python}" - "$RUN_DIR/summary.json" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
try:
    payload = json.loads(path.read_text(encoding='utf-8'))
except Exception:
    print('malformed')
    raise SystemExit(0)
print(payload.get('status', 'unknown'))
PY
)"
    [[ "$summary_status" == "completed" ]] || status_issues+=("summary.json.status=$summary_status")
  fi

  plot_status_path="$RUN_DIR/validation/plot-status.json"
  if [[ -f "$plot_status_path" ]]; then
    plot_status="$("${PYTHON_BIN:-python}" - "$plot_status_path" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
try:
    payload = json.loads(path.read_text(encoding='utf-8'))
except Exception:
    print('malformed')
    raise SystemExit(0)
print(payload.get('status', 'unknown'))
PY
)"
    case "$plot_status" in
      completed|skipped-disabled)
        ;;
      *)
        optional_missing+=("validation/plot-status.json status=$plot_status")
        ;;
    esac
  else
    optional_missing+=("$plot_status_path")
  fi
fi

if [[ "$PHASE" == "completed" || -f "$RUN_DIR/derived/workload-sql-set.json" || -f "$RUN_DIR/derived/workload-sql-set.md" ]]; then
  require_non_empty_file "$RUN_DIR/derived/workload-sql-set.json"
  require_non_empty_file "$RUN_DIR/derived/workload-sql-set.md"
fi

missing_json="$("${PYTHON_BIN:-python}" - "${missing[@]}" <<'PY'
import json
import sys
seen = []
for value in sys.argv[1:]:
    if value not in seen:
        seen.append(value)
print(json.dumps(seen))
PY
)"
optional_missing_json="$("${PYTHON_BIN:-python}" - "${optional_missing[@]}" <<'PY'
import json
import sys
seen = []
for value in sys.argv[1:]:
    if value not in seen:
        seen.append(value)
print(json.dumps(seen))
PY
)"
status_issues_json="$("${PYTHON_BIN:-python}" - "${status_issues[@]}" <<'PY'
import json
import sys
seen = []
for value in sys.argv[1:]:
    if value not in seen:
        seen.append(value)
print(json.dumps(seen))
PY
)"
validation_complete=true
[[ ${#missing[@]} -gt 0 || ${#status_issues[@]} -gt 0 ]] && validation_complete=false
cat > "$RUN_DIR/validation/artifact-check.json" <<EOF
{
  "missing_files": $missing_json,
  "optional_missing_files": $optional_missing_json,
  "status_issues": $status_issues_json,
  "validation_complete": $validation_complete,
  "report_bundle_status": "${report_bundle_status}",
  "report_bundle_missing_files": $report_bundle_missing_json
}
EOF

if ! $validation_complete; then
  echo "artifact validation failed for $RUN_DIR" >&2
  exit 1
fi
