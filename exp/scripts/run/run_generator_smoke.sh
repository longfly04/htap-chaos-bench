#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
EXP_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATASET_ROOT="${DATASET_ROOT:-$EXP_ROOT/datasets/${DATASET:-job}}"
RUN_DIR="${1:-}"
[[ -n "$RUN_DIR" ]] || { echo "run directory is required" >&2; exit 1; }
mkdir -p "$RUN_DIR/derived/generator" "$RUN_DIR/explainability" "$RUN_DIR/validation"

"${PYTHON_BIN:-python}" "$EXP_ROOT/generator/stats/export_stats.py" --dataset-root "$DATASET_ROOT" --output "$RUN_DIR/derived/generator/stats-export.json"
"${PYTHON_BIN:-python}" "$EXP_ROOT/generator/schema/build_schema_graph.py" --query-root "$DATASET_ROOT/queries/ap" --output "$RUN_DIR/derived/generator/schema-graph.json"
"${PYTHON_BIN:-python}" "$EXP_ROOT/generator/schema/weighted_walk.py" --graph "$RUN_DIR/derived/generator/schema-graph.json" --seed "${SEED:-1}" --output "$RUN_DIR/derived/generator/weighted-walk.json"
"${PYTHON_BIN:-python}" "$EXP_ROOT/generator/templates/gen_select_templates.py" --query-root "$DATASET_ROOT/queries/ap" --graph "$RUN_DIR/derived/generator/schema-graph.json" --seed "${SEED:-1}" --output "$RUN_DIR/derived/generator/select-templates.json"
"${PYTHON_BIN:-python}" "$EXP_ROOT/generator/templates/gen_update_templates.py" --graph "$RUN_DIR/derived/generator/schema-graph.json" --output "$RUN_DIR/derived/generator/update-templates.json"
"${PYTHON_BIN:-python}" "$EXP_ROOT/generator/drift/update_drift_controller.py" --templates "$RUN_DIR/derived/generator/update-templates.json" --output "$RUN_DIR/derived/generator/drift-plan.json"
"${PYTHON_BIN:-python}" "$EXP_ROOT/generator/instantiate_scenario.py" --select-templates "$RUN_DIR/derived/generator/select-templates.json" --update-templates "$RUN_DIR/derived/generator/update-templates.json" --seed "${SEED:-1}" --output "$RUN_DIR/derived/generator/scenario.json"
"${PYTHON_BIN:-python}" "$EXP_ROOT/scripts/validation/60_explainability_bundle.py" --run-dir "$RUN_DIR"
"$EXP_ROOT/scripts/validation/50_artifact_check.sh" --run-dir "$RUN_DIR"
printf 'completed\n' > "$RUN_DIR/run-status.txt"
cat > "$RUN_DIR/explainability/top-findings.md" <<EOF
- generator smoke produced schema graph, walks, select/update templates, drift plan, and instantiated scenario
- v0 generator is currently scoped to pg-like + JOB
EOF
