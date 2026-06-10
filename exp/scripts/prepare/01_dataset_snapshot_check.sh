#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
EXP_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUN_DIR=""
DATASET_ROOT="${DATASET_ROOT:-$EXP_ROOT/datasets/${DATASET:-job}}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)
      RUN_DIR="$2"
      shift 2
      ;;
    --dataset-root)
      DATASET_ROOT="$2"
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

schema_present=false
[[ -d "$DATASET_ROOT/schema" ]] && schema_present=true
stats_present=false
[[ -d "$DATASET_ROOT/stats" ]] && stats_present=true
classes_present=false
[[ -f "$DATASET_ROOT/queries/classes.yaml" ]] && classes_present=true
seed_present=false
if [[ -f "$DATASET_ROOT/tp_templates/seed1.sql" || -f "$DATASET_ROOT/tp/seeds/seed1.sql" ]]; then
  seed_present=true
fi
metadata_present=false
[[ -f "$DATASET_ROOT/metadata/dataset.env" ]] && metadata_present=true

cat > "$RUN_DIR/validation/dataset-check.json" <<EOF
{
  "dataset_root": "$DATASET_ROOT",
  "schema_present": $schema_present,
  "stats_present": $stats_present,
  "ap_classes_present": $classes_present,
  "tp_seed_present": $seed_present,
  "metadata_present": $metadata_present
}
EOF
