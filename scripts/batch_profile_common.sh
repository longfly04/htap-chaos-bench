#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${PROJECT_ROOT:-}" ]]; then
  PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fi

setup_batch_profile() {
  local requested_profile="${1:-${MEMORY_PROFILE:-4u4g}}"
  local env_file_rel
  case "$requested_profile" in
    4u4g|4u8g|8u8g|8u16g)
      env_file_rel="pglab/compose/profiles/${requested_profile}.env"
      ;;
    *)
      printf 'unsupported profile: %s\n' "$requested_profile" >&2
      return 1
      ;;
  esac

  export LAB_ROOT="$PROJECT_ROOT"
  export LAB_RUNTIME_MODE=container
  export LAB_ENV_FILE="$env_file_rel"

  local env_file_abs="$PROJECT_ROOT/$env_file_rel"
  [[ -f "$env_file_abs" ]] || {
    printf 'profile env not found: %s\n' "$env_file_abs" >&2
    return 1
  }

  set -a
  # shellcheck disable=SC1090
  source "$env_file_abs"
  set +a

  export MEMORY_PROFILE="${MEMORY_PROFILE:-$requested_profile}"
  export JOB_TP_DRIVER="${JOB_TP_DRIVER:-sysbench}"
  export SYSBENCH_BIN="${SYSBENCH_BIN:-/home/sducs/postgresql-dev/benchmarks/sysbench/src/sysbench}"
  export OBSERVE_SAMPLING_INTERVAL_SECONDS="${OBSERVE_SAMPLING_INTERVAL_SECONDS:-2}"
  export WARMUP_SECONDS="${WARMUP_SECONDS:-${JOB_WARMUP_SECONDS:-10}}"
  export DURATION_SECONDS="${DURATION_SECONDS:-${JOB_DURATION_SECONDS:-120}}"
  export MEASURE_SECONDS="${MEASURE_SECONDS:-${JOB_MEASURE_SECONDS:-120}}"
  export AP_PARALLELISM="${AP_PARALLELISM:-${JOB_AP_PARALLELISM:-0}}"
  export PLOT_PYTHON_BIN="${PLOT_PYTHON_BIN:-/home/sducs/miniconda3/bin/python}"
  export PYTHON_BIN="${PYTHON_BIN:-/home/sducs/miniconda3/bin/python}"
  export RUNS_ROOT="${RUNS_ROOT:-$PROJECT_ROOT/runs/$MEMORY_PROFILE}"
  export PROFILE_LOG_ROOT="${PROFILE_LOG_ROOT:-$PROJECT_ROOT/runs/batches/$MEMORY_PROFILE}"

  mkdir -p "$RUNS_ROOT" "$PROFILE_LOG_ROOT"
}
