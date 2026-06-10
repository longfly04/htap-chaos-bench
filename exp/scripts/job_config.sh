#!/usr/bin/env bash
set -euo pipefail

job_load_runtime_config() {
  local exp_root="${1:-${EXP_ROOT:-}}"
  local project_root="${PROJECT_ROOT:-}"
  local project_paths_env=""
  local runtime_env="${JOB_RUNTIME_ENV:-}"
  if [[ -z "$project_root" && -n "$exp_root" ]]; then
    project_root="$(cd "$exp_root/.." && pwd)"
  fi
  if [[ -n "$project_root" ]]; then
    PROJECT_ROOT="$project_root"
    project_paths_env="${PROJECT_PATHS_ENV:-$project_root/config/project-paths.env}"
    if [[ -f "$project_paths_env" ]]; then
      # shellcheck disable=SC1090
      source "$project_paths_env"
      export PROJECT_PATHS_ENV="$project_paths_env"
    fi
  fi
  if [[ -z "$runtime_env" && -n "$exp_root" ]]; then
    runtime_env="$exp_root/datasets/job/metadata/runtime.env"
  fi
  if [[ -n "$runtime_env" && -f "$runtime_env" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$runtime_env"
    set +a
    export JOB_RUNTIME_ENV="$runtime_env"
  fi
}

job_tp_threads_for_pressure() {
  case "${1:-medium}" in
    low) printf '%s\n' "${JOB_TP_THREADS_LOW:?missing JOB_TP_THREADS_LOW}" ;;
    medium) printf '%s\n' "${JOB_TP_THREADS_MEDIUM:?missing JOB_TP_THREADS_MEDIUM}" ;;
    high) printf '%s\n' "${JOB_TP_THREADS_HIGH:?missing JOB_TP_THREADS_HIGH}" ;;
    *) printf '%s\n' "${JOB_TP_THREADS_MEDIUM:?missing JOB_TP_THREADS_MEDIUM}" ;;
  esac
}

job_ap_query_file_for_class() {
  local exp_root="${1:-${EXP_ROOT:-}}"
  local ap_class="${2:-sort-heavy}"
  local dataset_root="${DATASET_ROOT:-}"
  if [[ -z "$dataset_root" && -n "$exp_root" ]]; then
    dataset_root="$exp_root/datasets/${DATASET:-job}"
  fi
  case "$ap_class" in
    sort-heavy) printf '%s\n' "$dataset_root/${JOB_AP_QUERY_SORT_HEAVY:?missing JOB_AP_QUERY_SORT_HEAVY}" ;;
    hash-heavy) printf '%s\n' "$dataset_root/${JOB_AP_QUERY_HASH_HEAVY:?missing JOB_AP_QUERY_HASH_HEAVY}" ;;
    mixed) printf '%s\n' "$dataset_root/${JOB_AP_QUERY_MIXED:?missing JOB_AP_QUERY_MIXED}" ;;
    *) printf '%s\n' "$dataset_root/${JOB_AP_QUERY_SORT_HEAVY:?missing JOB_AP_QUERY_SORT_HEAVY}" ;;
  esac
}

job_cleanup_unstable_window_ms() {
  case "${JOB_CHAOS_CLEANUP_PROFILE:-pg-default}" in
    pg-restart)
      printf '%s\n' "${JOB_CLEANUP_UNSTABLE_WINDOW_PG_RESTART_MS:?missing JOB_CLEANUP_UNSTABLE_WINDOW_PG_RESTART_MS}"
      ;;
    *)
      printf '%s\n' "${JOB_CLEANUP_UNSTABLE_WINDOW_PG_DEFAULT_MS:?missing JOB_CLEANUP_UNSTABLE_WINDOW_PG_DEFAULT_MS}"
      ;;
  esac
}
