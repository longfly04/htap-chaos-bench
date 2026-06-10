#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
EXP_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$EXP_ROOT/.." && pwd)"
# shellcheck disable=SC1090
source "$PROJECT_ROOT/config/project-paths.env"
source "${HARNESS_COMMON:-$PROJECT_ROOT/scripts/harness_common.sh}"

RUN_DIR=""
DATABASE="${BENCHMARK_DB_NAME:-${JOB_DB_NAME:-postgres}}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)
      RUN_DIR="$2"
      shift 2
      ;;
    --database)
      DATABASE="$2"
      shift 2
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done
[[ -n "$RUN_DIR" ]] || fail "--run-dir is required"
mkdir -p "$RUN_DIR/validation"

db_connectable=true
version_detail=""
available_extensions_raw=""
installed_extensions_raw=""
shared_preload_libraries=""
if version_detail="$(run_psql "$DATABASE" "select version()" 2>/dev/null)"; then
  available_extensions_raw="$(run_psql "$DATABASE" "select name from pg_available_extensions order by 1" 2>/dev/null || true)"
  installed_extensions_raw="$(run_psql "$DATABASE" "select extname from pg_extension order by 1" 2>/dev/null || true)"
  shared_preload_libraries="$(run_psql "$DATABASE" "select coalesce(current_setting('shared_preload_libraries', true), '')" 2>/dev/null || true)"
else
  db_connectable=false
  version_detail="unavailable"
fi

check_runtime_command() {
  local command_name="$1"
  if is_source_runtime; then
    command -v "$command_name" >/dev/null 2>&1
    return
  fi
  compose exec -T -e REQUIRED_COMMAND="$command_name" "${DB_SERVICE_NAME:-postgres}" sh -lc 'command -v "$REQUIRED_COMMAND" >/dev/null 2>&1'
}

resolve_runtime_command_path() {
  local command_name="$1"
  if is_source_runtime; then
    command -v "$command_name" 2>/dev/null || true
    return
  fi
  compose exec -T -e REQUIRED_COMMAND="$command_name" "${DB_SERVICE_NAME:-postgres}" sh -lc 'command -v "$REQUIRED_COMMAND" 2>/dev/null || true'
}

required_commands_raw="${OBSERVE_REQUIRED_COMMANDS:-}"
command_status_raw=""
if [[ -n "$required_commands_raw" ]]; then
  IFS=',' read -r -a required_commands <<< "$required_commands_raw"
  for command_name in "${required_commands[@]}"; do
    command_name="${command_name//[[:space:]]/}"
    [[ -n "$command_name" ]] || continue
    command_path="$(resolve_runtime_command_path "$command_name")"
    if check_runtime_command "$command_name"; then
      command_status_raw+="$command_name|true|$command_path"$'\n'
    else
      command_status_raw+="$command_name|false|"$'\n'
    fi
  done
fi

run_dir_writable=true
if ! touch "$RUN_DIR/.env-sanity.tmp" 2>/dev/null; then
  run_dir_writable=false
else
  rm -f "$RUN_DIR/.env-sanity.tmp"
fi

export ENV_SANITY_DATABASE_CONNECTABLE="$db_connectable"
export ENV_SANITY_DATABASE="$DATABASE"
export ENV_SANITY_VERSION="$version_detail"
export ENV_SANITY_RUN_DIR_WRITABLE="$run_dir_writable"
export ENV_SANITY_LAB_RUNTIME_MODE="${LAB_RUNTIME_MODE:-container}"
export ENV_SANITY_MEMORY_PROFILE="${MEMORY_PROFILE:-}"
export ENV_SANITY_LAB_ENV_FILE="${LAB_ENV_FILE:-}"
export ENV_SANITY_COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-}"
export ENV_SANITY_DB_SERVICE_NAME="${DB_SERVICE_NAME:-postgres}"
export ENV_SANITY_POSTGRES_IMAGE="${POSTGRES_IMAGE:-}"
export ENV_SANITY_CGROUP_CPU_LIMIT="${CGROUP_CPU_LIMIT:-}"
export ENV_SANITY_CGROUP_MEMORY_LIMIT="${CGROUP_MEMORY_LIMIT:-}"
export ENV_SANITY_CGROUP_MEMORY_RESERVATION="${CGROUP_MEMORY_RESERVATION:-}"
export ENV_SANITY_REQUIRED_EXTENSIONS="${OBSERVE_REQUIRED_EXTENSIONS:-}"
export ENV_SANITY_REQUIRED_PRELOAD_LIBRARIES="${OBSERVE_REQUIRED_PRELOAD_LIBRARIES:-}"
export ENV_SANITY_REQUIRED_COMMANDS="$required_commands_raw"
export ENV_SANITY_AVAILABLE_EXTENSIONS="$available_extensions_raw"
export ENV_SANITY_INSTALLED_EXTENSIONS="$installed_extensions_raw"
export ENV_SANITY_SHARED_PRELOAD_LIBRARIES="$shared_preload_libraries"
export ENV_SANITY_COMMAND_STATUS="$command_status_raw"

if ! "${PYTHON_BIN:-python}" - "$RUN_DIR/validation/env-sanity.json" <<'PY'
import json
import os
import sys

output_path = sys.argv[1]


def split_csv(raw: str) -> list[str]:
    return [item.strip() for item in raw.split(",") if item.strip()]


def split_lines(raw: str) -> list[str]:
    return [item.strip() for item in raw.splitlines() if item.strip()]


def to_bool(raw: str) -> bool:
    return raw.strip().lower() in {"1", "true", "yes", "on"}


database_connectable = to_bool(os.environ.get("ENV_SANITY_DATABASE_CONNECTABLE", "false"))
run_dir_writable = to_bool(os.environ.get("ENV_SANITY_RUN_DIR_WRITABLE", "false"))
required_extensions = split_csv(os.environ.get("ENV_SANITY_REQUIRED_EXTENSIONS", ""))
required_preload_libraries = split_csv(os.environ.get("ENV_SANITY_REQUIRED_PRELOAD_LIBRARIES", ""))
required_commands = split_csv(os.environ.get("ENV_SANITY_REQUIRED_COMMANDS", ""))
available_extensions = split_lines(os.environ.get("ENV_SANITY_AVAILABLE_EXTENSIONS", ""))
installed_extensions = split_lines(os.environ.get("ENV_SANITY_INSTALLED_EXTENSIONS", ""))
shared_preload_libraries = split_csv(os.environ.get("ENV_SANITY_SHARED_PRELOAD_LIBRARIES", ""))
command_status_lines = split_lines(os.environ.get("ENV_SANITY_COMMAND_STATUS", ""))

available_set = set(available_extensions)
installed_set = set(installed_extensions)
shared_preload_set = set(shared_preload_libraries)

extension_status = [
    {
        "name": name,
        "available": name in available_set,
        "installed": name in installed_set,
    }
    for name in required_extensions
]
preload_library_status = [
    {
        "name": name,
        "configured": name in shared_preload_set,
    }
    for name in required_preload_libraries
]
command_status = []
for line in command_status_lines:
    name, available, path = (line.split("|", 2) + ["", "", ""])[:3]
    if not name:
        continue
    command_status.append(
        {
            "name": name,
            "available": available.lower() == "true",
            "path": path,
        }
    )
missing_extensions = [item["name"] for item in extension_status if not item["available"]]
missing_preload_libraries = [item["name"] for item in preload_library_status if not item["configured"]]
missing_commands = [item["name"] for item in command_status if not item["available"]]

failures: list[str] = []
if not database_connectable:
    failures.append("database-connectivity")
if not run_dir_writable:
    failures.append("run-dir-not-writable")
if missing_extensions:
    failures.append("missing-extensions")
if missing_preload_libraries:
    failures.append("missing-preload-libraries")
if missing_commands:
    failures.append("missing-commands")

report = {
    "database_connectable": database_connectable,
    "database": os.environ.get("ENV_SANITY_DATABASE", ""),
    "version": os.environ.get("ENV_SANITY_VERSION", ""),
    "run_dir_writable": run_dir_writable,
    "lab_runtime_mode": os.environ.get("ENV_SANITY_LAB_RUNTIME_MODE", "container"),
    "memory_profile": os.environ.get("ENV_SANITY_MEMORY_PROFILE", ""),
    "lab_env_file": os.environ.get("ENV_SANITY_LAB_ENV_FILE", ""),
    "compose_project_name": os.environ.get("ENV_SANITY_COMPOSE_PROJECT_NAME", ""),
    "db_service_name": os.environ.get("ENV_SANITY_DB_SERVICE_NAME", "postgres"),
    "postgres_image": os.environ.get("ENV_SANITY_POSTGRES_IMAGE", ""),
    "cgroup_cpu_limit": os.environ.get("ENV_SANITY_CGROUP_CPU_LIMIT", ""),
    "cgroup_memory_limit": os.environ.get("ENV_SANITY_CGROUP_MEMORY_LIMIT", ""),
    "cgroup_memory_reservation": os.environ.get("ENV_SANITY_CGROUP_MEMORY_RESERVATION", ""),
    "required_extensions": required_extensions,
    "required_preload_libraries": required_preload_libraries,
    "required_commands": required_commands,
    "available_extensions": available_extensions,
    "installed_extensions": installed_extensions,
    "shared_preload_libraries": shared_preload_libraries,
    "extension_status": extension_status,
    "preload_library_status": preload_library_status,
    "command_status": command_status,
    "missing_extensions": missing_extensions,
    "missing_preload_libraries": missing_preload_libraries,
    "missing_commands": missing_commands,
    "extension_preflight_ok": not missing_extensions and not missing_preload_libraries,
    "command_preflight_ok": not missing_commands,
    "failures": failures,
}

with open(output_path, "w", encoding="utf-8") as fh:
    json.dump(report, fh, indent=2, ensure_ascii=False)
    fh.write("\n")

raise SystemExit(0 if not failures else 1)
PY
then
  fail "environment sanity check failed: see $RUN_DIR/validation/env-sanity.json"
fi
