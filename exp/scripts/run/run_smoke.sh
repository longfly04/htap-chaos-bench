#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
EXP_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$EXP_ROOT/.." && pwd)"
# shellcheck disable=SC1090
source "$PROJECT_ROOT/config/project-paths.env"
RUN_DIR="${1:-}"
[[ -n "$RUN_DIR" ]] || { echo "run directory is required" >&2; exit 1; }
mkdir -p "$RUN_DIR/validation" "$RUN_DIR/explainability" "$RUN_DIR/metrics"

"$EXP_ROOT/scripts/prepare/00_env_sanity.sh" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/prepare/03_job_first_prepare.sh" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/prepare/01_dataset_snapshot_check.sh" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/prepare/02_adapter_capabilities.sh" --run-dir "$RUN_DIR"
"${HARNESS_EXPORT_RUN_ARTIFACTS:-$PROJECT_ROOT/scripts/harness_export_run_artifacts.sh}" --run-dir "$RUN_DIR" || true
"$EXP_ROOT/scripts/validation/10_metrics_liveness.sh" --run-dir "$RUN_DIR"
"${PYTHON_BIN:-python}" "$EXP_ROOT/scripts/validation/60_explainability_bundle.py" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/validation/50_artifact_check.sh" --run-dir "$RUN_DIR"
printf 'completed\n' > "$RUN_DIR/run-status.txt"
cat > "$RUN_DIR/explainability/top-findings.md" <<'EOF'
- smoke run completed the paper1 Phase 0.5 validation path
- shared harness emitted canonical run identity and observability snapshots
EOF
